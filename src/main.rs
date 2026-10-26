use anyhow::{Result, anyhow};
use clap::Arg;
use notify::{Event, EventKind, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::{Mutex, RwLock, mpsc};
use tower_lsp::lsp_types::*;

/// Handshake-based MCP revisions this server speaks, oldest first. It only
/// uses `initialize`, `tools/list` and `tools/call`, which these share.
/// The stateless 2026-07-28 revision (`server/discover`) is not implemented.
const SUPPORTED_PROTOCOL_VERSIONS: [&str; 4] =
    ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"];

/// Echo the client's requested version when supported, else offer our newest.
fn negotiate_protocol_version(params: Option<&Value>) -> &'static str {
    let requested = params
        .and_then(|p| p.get("protocolVersion"))
        .and_then(Value::as_str);
    SUPPORTED_PROTOCOL_VERSIONS
        .iter()
        .copied()
        .find(|v| Some(*v) == requested)
        .unwrap_or(SUPPORTED_PROTOCOL_VERSIONS[SUPPORTED_PROTOCOL_VERSIONS.len() - 1])
}

// MCP Protocol types
#[derive(Debug, Serialize, Deserialize)]
pub struct McpRequest {
    pub jsonrpc: String,
    pub id: Option<Value>,
    pub method: String,
    pub params: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct McpResponse {
    pub jsonrpc: String,
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<McpError>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct McpError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    #[serde(rename = "inputSchema")]
    pub input_schema: Value,
}

// LSP Protocol types
#[derive(Debug, Serialize, Deserialize)]
struct LspRequest {
    jsonrpc: String,
    id: i64,
    method: String,
    params: Value,
}

#[derive(Debug, Serialize, Deserialize)]
struct LspNotification {
    jsonrpc: String,
    method: String,
    params: Value,
}

// Analysis state for tracking workspace information
#[derive(Debug, Clone)]
pub struct AnalysisState {
    pub is_updating: bool,
    pub last_update: Option<Instant>,
    pub file_versions: HashMap<PathBuf, u64>,
    pub diagnostics: HashMap<PathBuf, Vec<Diagnostic>>,
    pub workspace_root: Option<PathBuf>,
    /// rust-analyzer finished loading/indexing (experimental/serverStatus).
    pub quiescent: bool,
}

// LSP Client for communicating with rust-analyzer
pub struct LspClient {
    stdin: Arc<Mutex<tokio::process::ChildStdin>>,
    request_id: Arc<Mutex<i64>>,
    pending_requests: PendingRequests,
    _child: Child,
}

type PendingRequests =
    Arc<RwLock<HashMap<i64, tokio::sync::oneshot::Sender<std::result::Result<Value, String>>>>>;

fn path_to_uri(path: &Path) -> Result<Url> {
    let abs = std::path::absolute(path)?;
    Url::from_file_path(&abs).map_err(|_| anyhow!("Cannot convert {} to a file URI", abs.display()))
}

/// Key for the diagnostics map. rust-analyzer may report `c:/x` for a file we
/// opened as `C:/x`, so compare Windows paths case-insensitively.
fn diag_key(path: &Path) -> PathBuf {
    if cfg!(windows) {
        PathBuf::from(path.to_string_lossy().to_lowercase())
    } else {
        path.to_path_buf()
    }
}

/// Directories `analyze_workspace` does not descend into.
fn is_skipped_dir(name: &str) -> bool {
    name == "target" || name.starts_with('.')
}

fn is_rust_file(path: &Path) -> bool {
    path.extension().is_some_and(|ext| ext == "rs")
}

/// Read LSP messages from rust-analyzer's stdout until it closes.
/// Responses resolve pending requests, `publishDiagnostics` is stored in the
/// analysis state, and server-to-client requests get a null reply.
async fn lsp_reader(
    stdout: tokio::process::ChildStdout,
    stdin: Arc<Mutex<tokio::process::ChildStdin>>,
    pending: PendingRequests,
    state: Arc<RwLock<AnalysisState>>,
) {
    let mut reader = BufReader::new(stdout);
    loop {
        let mut content_length: Option<usize> = None;
        loop {
            let mut header = String::new();
            match reader.read_line(&mut header).await {
                Ok(0) | Err(_) => return,
                Ok(_) => {}
            }
            let header = header.trim();
            if header.is_empty() {
                break;
            }
            if let Some(v) = header.strip_prefix("Content-Length:") {
                content_length = v.trim().parse().ok();
            }
        }
        let Some(len) = content_length else { continue };
        let mut body = vec![0u8; len];
        if tokio::io::AsyncReadExt::read_exact(&mut reader, &mut body)
            .await
            .is_err()
        {
            return;
        }
        let Ok(msg) = serde_json::from_slice::<Value>(&body) else {
            continue;
        };

        match (msg.get("id"), msg.get("method").and_then(Value::as_str)) {
            (Some(id), Some(_)) => {
                // Server-to-client request (progress create, configuration, ...).
                let reply = json!({"jsonrpc": "2.0", "id": id, "result": null}).to_string();
                let framed = format!("Content-Length: {}\r\n\r\n{}", reply.len(), reply);
                let mut stdin = stdin.lock().await;
                let _ = stdin.write_all(framed.as_bytes()).await;
                let _ = stdin.flush().await;
            }
            (Some(id), None) => {
                let tx = match id.as_i64() {
                    Some(id) => pending.write().await.remove(&id),
                    None => None,
                };
                if let Some(tx) = tx {
                    let outcome = match msg.get("error") {
                        Some(err) => Err(err.to_string()),
                        None => Ok(msg.get("result").cloned().unwrap_or(Value::Null)),
                    };
                    let _ = tx.send(outcome);
                }
            }
            (None, Some("textDocument/publishDiagnostics")) => {
                if let Some(params) = msg.get("params").and_then(|p| {
                    serde_json::from_value::<PublishDiagnosticsParams>(p.clone()).ok()
                }) {
                    if let Ok(path) = params.uri.to_file_path() {
                        state
                            .write()
                            .await
                            .diagnostics
                            .insert(diag_key(&path), params.diagnostics);
                    }
                }
            }
            (None, Some("experimental/serverStatus")) => {
                let quiescent = msg["params"]["quiescent"].as_bool().unwrap_or(false);
                state.write().await.quiescent = quiescent;
            }
            _ => {}
        }
    }
}

// MCP Server for rust-analyzer integration
pub struct RustAnalyzerMcpServer {
    lsp_client: Arc<RwLock<Option<LspClient>>>,
    analysis_state: Arc<RwLock<AnalysisState>>,
    file_watcher: Arc<Mutex<Option<notify::RecommendedWatcher>>>,
}

impl Default for RustAnalyzerMcpServer {
    fn default() -> Self {
        Self::new()
    }
}

impl RustAnalyzerMcpServer {
    pub fn new() -> Self {
        Self {
            lsp_client: Arc::new(RwLock::new(None)),
            analysis_state: Arc::new(RwLock::new(AnalysisState {
                is_updating: false,
                last_update: None,
                file_versions: HashMap::new(),
                diagnostics: HashMap::new(),
                workspace_root: None,
                quiescent: false,
            })),
            file_watcher: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn initialize_rust_analyzer(&self, workspace_root: PathBuf) -> Result<()> {
        let workspace_root = std::path::absolute(&workspace_root)?;
        let mut child = Command::new("rust-analyzer")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::inherit())
            .kill_on_drop(true)
            .spawn()?;

        let stdin = Arc::new(Mutex::new(
            child
                .stdin
                .take()
                .ok_or_else(|| anyhow!("Failed to open stdin"))?,
        ));
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("Failed to open stdout"))?;

        let pending: PendingRequests = Arc::new(RwLock::new(HashMap::new()));
        tokio::spawn(lsp_reader(
            stdout,
            stdin.clone(),
            pending.clone(),
            self.analysis_state.clone(),
        ));

        let lsp_client = LspClient {
            stdin,
            request_id: Arc::new(Mutex::new(1)),
            pending_requests: pending,
            _child: child,
        };

        let root_uri = path_to_uri(&workspace_root)?;
        let initialize_params = json!({
            "processId": std::process::id(),
            "rootUri": root_uri,
            "capabilities": {
                "textDocument": {"publishDiagnostics": {}},
                "experimental": {"serverStatusNotification": true}
            },
            "workspaceFolders": [{
                "uri": root_uri,
                "name": workspace_root.file_name().unwrap_or_default().to_string_lossy()
            }]
        });

        lsp_client
            .send_request("initialize", initialize_params)
            .await?;
        lsp_client
            .send_notification("initialized", json!({}))
            .await?;

        {
            let mut state = self.analysis_state.write().await;
            state.workspace_root = Some(workspace_root.clone());
        }

        *self.lsp_client.write().await = Some(lsp_client);

        self.start_file_watcher(workspace_root).await?;

        Ok(())
    }

    async fn start_file_watcher(&self, workspace_root: PathBuf) -> Result<()> {
        let analysis_state = self.analysis_state.clone();
        let lsp_client = self.lsp_client.clone();

        let (tx, mut rx) = mpsc::channel(100);

        let mut watcher = notify::recommended_watcher(move |res: notify::Result<Event>| {
            if let Ok(event) = res {
                if tx.blocking_send(event).is_err() {
                    eprintln!("Failed to send file event");
                }
            }
        })?;

        watcher.watch(&workspace_root, RecursiveMode::Recursive)?;

        // Store watcher
        *self.file_watcher.lock().await = Some(watcher);

        // Spawn task to handle file events
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                if let EventKind::Modify(_) | EventKind::Create(_) | EventKind::Remove(_) =
                    event.kind
                {
                    for path in &event.paths {
                        if path.extension().is_some_and(|ext| ext == "rs") {
                            // Notify LSP about file changes
                            if let Some(client) = lsp_client.read().await.as_ref() {
                                let _ =
                                    Self::handle_file_change(client, path, &analysis_state).await;
                            }
                        }
                    }
                }
            }
        });

        Ok(())
    }

    /// Tell rust-analyzer the current content of `path`: didOpen the first
    /// time, didChange (full text, next version) afterwards.
    async fn handle_file_change(
        client: &LspClient,
        path: &Path,
        analysis_state: &Arc<RwLock<AnalysisState>>,
    ) -> Result<()> {
        let uri = path_to_uri(path)?;
        let content = tokio::fs::read_to_string(path).await.unwrap_or_default();

        let version = {
            let mut state = analysis_state.write().await;
            let version = state.file_versions.get(path).map_or(1, |v| v + 1);
            state.file_versions.insert(path.to_path_buf(), version);
            state.last_update = Some(Instant::now());
            version
        };

        if version == 1 {
            client
                .send_notification(
                    "textDocument/didOpen",
                    json!({"textDocument": {
                        "uri": uri, "languageId": "rust", "version": version, "text": content
                    }}),
                )
                .await
        } else {
            client
                .send_notification(
                    "textDocument/didChange",
                    json!({
                        "textDocument": {"uri": uri, "version": version},
                        "contentChanges": [{"text": content}]
                    }),
                )
                .await
        }
    }

    pub async fn handle_mcp_request(&self, request: McpRequest) -> Result<McpResponse> {
        let result = match request.method.as_str() {
            "tools/list" => self.list_tools().await,
            "tools/call" => self.call_tool(request.params).await,
            "initialize" => Ok(json!({
                "protocolVersion": negotiate_protocol_version(request.params.as_ref()),
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "rust-analyzer-mcp-server",
                    "version": env!("CARGO_PKG_VERSION")
                }
            })),
            _ => Err(anyhow!("Unknown method: {}", request.method)),
        };

        match result {
            Ok(res) => Ok(McpResponse {
                jsonrpc: "2.0".to_string(),
                id: request.id,
                result: Some(res),
                error: None,
            }),
            Err(err) => Ok(McpResponse {
                jsonrpc: "2.0".to_string(),
                id: request.id,
                result: None,
                error: Some(McpError {
                    code: -32603,
                    message: err.to_string(),
                    data: None,
                }),
            }),
        }
    }

    async fn list_tools(&self) -> Result<Value> {
        let tools = vec![
            ToolDefinition {
                name: "get_diagnostics".to_string(),
                description: "Get diagnostics for a Rust file".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "Path to the Rust file"
                        }
                    },
                    "required": ["file_path"]
                }),
            },
            ToolDefinition {
                name: "get_hover_info".to_string(),
                description: "Get hover information for a symbol at a specific position"
                    .to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string"},
                        "line": {"type": "integer"},
                        "character": {"type": "integer"}
                    },
                    "required": ["file_path", "line", "character"]
                }),
            },
            ToolDefinition {
                name: "goto_definition".to_string(),
                description: "Go to definition of a symbol".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string"},
                        "line": {"type": "integer"},
                        "character": {"type": "integer"}
                    },
                    "required": ["file_path", "line", "character"]
                }),
            },
            ToolDefinition {
                name: "find_references".to_string(),
                description: "Find all references to a symbol".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string"},
                        "line": {"type": "integer"},
                        "character": {"type": "integer"}
                    },
                    "required": ["file_path", "line", "character"]
                }),
            },
            ToolDefinition {
                name: "get_completions".to_string(),
                description: "Get code completions at a specific position".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string"},
                        "line": {"type": "integer"},
                        "character": {"type": "integer"}
                    },
                    "required": ["file_path", "line", "character"]
                }),
            },
            ToolDefinition {
                name: "analyze_workspace".to_string(),
                description: "Analyze the entire workspace for issues".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {},
                    "additionalProperties": false
                }),
            },
        ];

        Ok(json!({ "tools": tools }))
    }

    async fn call_tool(&self, params: Option<Value>) -> Result<Value> {
        let params = params.ok_or_else(|| anyhow!("No parameters provided"))?;
        let tool_name = params["name"]
            .as_str()
            .ok_or_else(|| anyhow!("No tool name provided"))?;
        let arguments = params.get("arguments").cloned().unwrap_or(json!({}));

        match tool_name {
            "get_diagnostics" => self.get_diagnostics(arguments).await,
            "get_hover_info" => self.get_hover_info(arguments).await,
            "goto_definition" => self.goto_definition(arguments).await,
            "find_references" => self.find_references(arguments).await,
            "get_completions" => self.get_completions(arguments).await,
            "analyze_workspace" => self.analyze_workspace().await,
            _ => Err(anyhow!("Unknown tool: {}", tool_name)),
        }
    }

    async fn get_diagnostics(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"]
            .as_str()
            .ok_or_else(|| anyhow!("file_path required"))?;
        let client_guard = self.lsp_client.read().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let key = diag_key(&std::path::absolute(file_path)?);
        self.analysis_state.write().await.diagnostics.remove(&key);
        self.open_document(client, file_path).await?;

        // rust-analyzer pushes diagnostics asynchronously; wait for them.
        let deadline = Instant::now() + Duration::from_secs(90);
        let mut resynced = false;
        let diagnostics = loop {
            let quiescent = self.analysis_state.read().await.quiescent;
            if quiescent && !resynced {
                // Anything published while the project was still loading is
                // incomplete: ask again now that analysis can see everything.
                resynced = true;
                self.analysis_state.write().await.diagnostics.remove(&key);
                self.open_document(client, file_path).await?;
            } else if quiescent {
                if let Some(d) = self.analysis_state.read().await.diagnostics.get(&key) {
                    break d.clone();
                }
            }
            if Instant::now() >= deadline {
                return Err(anyhow!("Timed out waiting for diagnostics for {file_path}"));
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        };
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Diagnostics for {}: {}", file_path, serde_json::to_string(&diagnostics)?)
            }]
        }))
    }

    /// Like `open_document`, but first waits for rust-analyzer to finish loading
    /// the project; queries sent earlier are answered with empty results.
    async fn open_ready_document(&self, client: &LspClient, file_path: &str) -> Result<Url> {
        let deadline = Instant::now() + Duration::from_secs(300);
        while !self.analysis_state.read().await.quiescent {
            if Instant::now() >= deadline {
                return Err(anyhow!(
                    "Timed out waiting for rust-analyzer to finish loading the project"
                ));
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        self.open_document(client, file_path).await
    }

    /// Sync the file's current content to rust-analyzer and return its URI.
    async fn open_document(&self, client: &LspClient, file_path: &str) -> Result<Url> {
        let path = std::path::absolute(file_path)?;
        Self::handle_file_change(client, &path, &self.analysis_state).await?;
        path_to_uri(&path)
    }

    async fn get_hover_info(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"]
            .as_str()
            .ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"]
            .as_u64()
            .ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"]
            .as_u64()
            .ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = self.open_ready_document(client, file_path).await?;
        let params = json!({
            "textDocument": {
                "uri": uri
            },
            "position": {
                "line": line,
                "character": character
            }
        });

        let response = client.send_request("textDocument/hover", params).await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Hover info: {}", response)
            }]
        }))
    }

    async fn goto_definition(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"]
            .as_str()
            .ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"]
            .as_u64()
            .ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"]
            .as_u64()
            .ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = self.open_ready_document(client, file_path).await?;
        let params = json!({
            "textDocument": {
                "uri": uri
            },
            "position": {
                "line": line,
                "character": character
            }
        });

        let response = client
            .send_request("textDocument/definition", params)
            .await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Definition: {}", response)
            }]
        }))
    }

    async fn find_references(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"]
            .as_str()
            .ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"]
            .as_u64()
            .ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"]
            .as_u64()
            .ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = self.open_ready_document(client, file_path).await?;
        let params = json!({
            "textDocument": {
                "uri": uri
            },
            "position": {
                "line": line,
                "character": character
            },
            "context": {
                "includeDeclaration": true
            }
        });

        let response = client
            .send_request("textDocument/references", params)
            .await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("References: {}", response)
            }]
        }))
    }

    async fn get_completions(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"]
            .as_str()
            .ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"]
            .as_u64()
            .ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"]
            .as_u64()
            .ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard
            .as_ref()
            .ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = self.open_ready_document(client, file_path).await?;
        let params = json!({
            "textDocument": {
                "uri": uri
            },
            "position": {
                "line": line,
                "character": character
            }
        });

        let response = client
            .send_request("textDocument/completion", params)
            .await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Completions: {}", response)
            }]
        }))
    }

    async fn analyze_workspace(&self) -> Result<Value> {
        let state = self.analysis_state.read().await;
        let workspace_root = state
            .workspace_root
            .as_ref()
            .ok_or_else(|| anyhow!("Workspace not initialized"))?;

        let mut analysis_results = Vec::new();

        // Get all Rust files in workspace
        let rust_files = Self::find_rust_files(workspace_root).await?;

        for file in rust_files {
            if let Ok(diagnostics) = self
                .get_diagnostics(json!({"file_path": file.display().to_string()}))
                .await
            {
                analysis_results.push(json!({
                    "file": file.display().to_string(),
                    "diagnostics": diagnostics
                }));
            }
        }

        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Workspace analysis complete. Analyzed {} files.", analysis_results.len())
            }]
        }))
    }

    fn find_rust_files(
        dir: &Path,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Vec<PathBuf>>> + Send + '_>>
    {
        Box::pin(async move {
            let mut rust_files = Vec::new();
            let mut entries = tokio::fs::read_dir(dir).await?;

            while let Some(entry) = entries.next_entry().await? {
                let path = entry.path();
                if path.is_dir() {
                    if !is_skipped_dir(&entry.file_name().to_string_lossy()) {
                        if let Ok(mut sub_files) = Self::find_rust_files(&path).await {
                            rust_files.append(&mut sub_files);
                        }
                    }
                } else if is_rust_file(&path) {
                    rust_files.push(path);
                }
            }

            Ok(rust_files)
        })
    }
}

impl LspClient {
    async fn send_request(&self, method: &str, params: Value) -> Result<Value> {
        let id = {
            let mut req_id = self.request_id.lock().await;
            let id = *req_id;
            *req_id += 1;
            id
        };

        let request = LspRequest {
            jsonrpc: "2.0".to_string(),
            id,
            method: method.to_string(),
            params,
        };

        let request_json = serde_json::to_string(&request)?;
        let message = format!(
            "Content-Length: {}\r\n\r\n{}",
            request_json.len(),
            request_json
        );

        // Create a channel for the response
        let (tx, rx) = tokio::sync::oneshot::channel();
        self.pending_requests.write().await.insert(id, tx);

        {
            let mut stdin = self.stdin.lock().await;
            stdin.write_all(message.as_bytes()).await?;
            stdin.flush().await?;
        }

        // Wait for response with timeout
        match tokio::time::timeout(Duration::from_secs(30), rx).await {
            Ok(Ok(Ok(value))) => Ok(value),
            Ok(Ok(Err(e))) => Err(anyhow!("rust-analyzer error: {e}")),
            Ok(Err(_)) => Err(anyhow!("rust-analyzer exited before answering {method}")),
            Err(_) => {
                self.pending_requests.write().await.remove(&id);
                Err(anyhow!(
                    "Timed out waiting for rust-analyzer to answer {method}"
                ))
            }
        }
    }

    async fn send_notification(&self, method: &str, params: Value) -> Result<()> {
        let notification = LspNotification {
            jsonrpc: "2.0".to_string(),
            method: method.to_string(),
            params,
        };

        let notification_json = serde_json::to_string(&notification)?;
        let message = format!(
            "Content-Length: {}\r\n\r\n{}",
            notification_json.len(),
            notification_json
        );

        let mut stdin = self.stdin.lock().await;
        stdin.write_all(message.as_bytes()).await?;
        stdin.flush().await?;

        Ok(())
    }
}

// CLI argument parsing
#[derive(Debug)]
struct CliArgs {
    workspace_root: PathBuf,
}

fn parse_args() -> CliArgs {
    let app = clap::Command::new("rust-analyzer-mcp-server")
        .version(env!("CARGO_PKG_VERSION"))
        .about("🦀 MCP Server for rust-analyzer integration")
        .author("CireSnave")
        .arg(
            Arg::new("workspace")
                .help("Workspace root directory")
                .value_name("WORKSPACE")
                .index(1),
        );

    let matches = app.get_matches();

    let workspace_root = if let Some(workspace) = matches.get_one::<String>("workspace") {
        PathBuf::from(workspace)
    } else {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
    };

    CliArgs { workspace_root }
}

fn print_startup_banner(workspace_root: &Path) {
    eprintln!();
    eprintln!("╔══════════════════════════════════════════════════════════════╗");
    eprintln!(
        "║  🦀 Rust Analyzer MCP Server v{:<10}                      ║",
        env!("CARGO_PKG_VERSION")
    );
    eprintln!("╚══════════════════════════════════════════════════════════════╝");
    eprintln!();
    eprintln!(
        "🚀 Starting MCP server for workspace: {}",
        workspace_root.display()
    );
    eprintln!();
    eprintln!("🛠️  Available Tools:");
    eprintln!("  📊 get_diagnostics     Get diagnostics for a Rust file");
    eprintln!("  💡 get_hover_info       Get hover information for a symbol");
    eprintln!("  🎯 goto_definition      Go to definition of a symbol");
    eprintln!("  🔍 find_references      Find all references to a symbol");
    eprintln!("  ✨ get_completions      Get code completions");
    eprintln!("  🔬 analyze_workspace    Analyze the entire workspace");
    eprintln!();
    eprintln!("📡 MCP Protocol: Ready for client connections");
    eprintln!("💻 Listening on stdin/stdout for MCP requests...");
    eprintln!();
}

fn print_initialization_error(error: &anyhow::Error) {
    eprintln!("⚠️  Warning: Failed to initialize rust-analyzer");
    eprintln!("   Error: {}", error);
    eprintln!("   The MCP server will run with limited functionality");
    eprintln!("   Please ensure rust-analyzer is installed and accessible");
    eprintln!();
}

// Main function to run the MCP server
#[tokio::main]
async fn main() -> Result<()> {
    let args = parse_args();
    let workspace_root = args.workspace_root;

    // Print startup banner
    print_startup_banner(&workspace_root);

    let server = RustAnalyzerMcpServer::new();

    // Initialize rust-analyzer
    if let Err(e) = server
        .initialize_rust_analyzer(workspace_root.clone())
        .await
    {
        print_initialization_error(&e);
    } else {
        eprintln!("✅ rust-analyzer initialized successfully");
        eprintln!();
    }

    // Simple stdin/stdout MCP protocol handler
    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin);
    let mut line = String::new();

    loop {
        line.clear();
        match reader.read_line(&mut line).await {
            Ok(0) => break, // EOF
            Ok(_) => {
                if line.trim().is_empty() {
                    continue;
                }

                // Try to parse as MCP request
                if let Ok(request) = serde_json::from_str::<McpRequest>(line.trim()) {
                    // Notifications (no id, e.g. notifications/initialized) get no reply.
                    if request.id.is_none() {
                        continue;
                    }
                    let response = server
                        .handle_mcp_request(request)
                        .await
                        .unwrap_or_else(|e| McpResponse {
                            jsonrpc: "2.0".to_string(),
                            id: None,
                            result: None,
                            error: Some(McpError {
                                code: -32603,
                                message: e.to_string(),
                                data: None,
                            }),
                        });

                    if let Ok(response_json) = serde_json::to_string(&response) {
                        println!("{response_json}");
                    }
                }
            }
            Err(_) => break,
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[tokio::test]
    async fn test_server_creation() {
        let server = RustAnalyzerMcpServer::new();
        assert!(server.lsp_client.read().await.is_none());
    }

    #[tokio::test]
    async fn test_list_tools() {
        let server = RustAnalyzerMcpServer::new();
        let result = server.list_tools().await.unwrap();

        let tools = result["tools"].as_array().unwrap();
        assert_eq!(tools.len(), 6);

        let tool_names: Vec<&str> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();

        assert!(tool_names.contains(&"get_diagnostics"));
        assert!(tool_names.contains(&"get_hover_info"));
        assert!(tool_names.contains(&"goto_definition"));
        assert!(tool_names.contains(&"find_references"));
        assert!(tool_names.contains(&"get_completions"));
        assert!(tool_names.contains(&"analyze_workspace"));
    }

    #[tokio::test]
    async fn test_mcp_initialize() {
        let server = RustAnalyzerMcpServer::new();
        let request = McpRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(json!(1)),
            method: "initialize".to_string(),
            params: None,
        };

        let response = server.handle_mcp_request(request).await.unwrap();
        assert!(response.result.is_some());
        assert!(response.error.is_none());

        let result = response.result.unwrap();
        // No version requested: offer our newest.
        assert_eq!(result["protocolVersion"], "2025-11-25");
        assert!(result["capabilities"]["tools"].is_object());
    }

    #[test]
    fn test_protocol_negotiation() {
        let ask = |v: &str| negotiate_protocol_version(Some(&json!({"protocolVersion": v})));
        assert_eq!(ask("2024-11-05"), "2024-11-05");
        assert_eq!(ask("2025-06-18"), "2025-06-18");
        assert_eq!(ask("2099-01-01"), "2025-11-25");
        assert_eq!(negotiate_protocol_version(None), "2025-11-25");
    }

    #[tokio::test]
    async fn test_tools_list_request() {
        let server = RustAnalyzerMcpServer::new();
        let request = McpRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(json!(1)),
            method: "tools/list".to_string(),
            params: None,
        };

        let response = server.handle_mcp_request(request).await.unwrap();
        assert!(response.result.is_some());
        assert!(response.error.is_none());
    }

    #[tokio::test]
    async fn test_unknown_method() {
        let server = RustAnalyzerMcpServer::new();
        let request = McpRequest {
            jsonrpc: "2.0".to_string(),
            id: Some(json!(1)),
            method: "unknown/method".to_string(),
            params: None,
        };

        let response = server.handle_mcp_request(request).await.unwrap();
        assert!(response.result.is_none());
        assert!(response.error.is_some());
        assert_eq!(response.error.unwrap().code, -32603);
    }

    #[tokio::test]
    async fn test_find_rust_files() {
        let temp_dir = TempDir::new().unwrap();
        let temp_path = temp_dir.path();

        // Create some test files
        fs::write(temp_path.join("main.rs"), "fn main() {}").unwrap();
        fs::write(temp_path.join("lib.rs"), "pub fn test() {}").unwrap();
        fs::write(temp_path.join("README.md"), "# Test").unwrap();

        // Create a subdirectory with more rust files
        let sub_dir = temp_path.join("src");
        fs::create_dir(&sub_dir).unwrap();
        fs::write(sub_dir.join("module.rs"), "pub mod test;").unwrap();

        let rust_files = RustAnalyzerMcpServer::find_rust_files(temp_path)
            .await
            .unwrap();

        // Should find 3 rust files
        assert_eq!(rust_files.len(), 3);

        let file_names: Vec<String> = rust_files
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
            .collect();

        assert!(file_names.contains(&"main.rs".to_string()));
        assert!(file_names.contains(&"lib.rs".to_string()));
        assert!(file_names.contains(&"module.rs".to_string()));
    }

    /// Regression test for issue #1: startup must complete the LSP handshake
    /// against a real rust-analyzer and record the workspace, so tools work.
    /// Needs `rust-analyzer` on PATH (CI: `rustup component add rust-analyzer`).
    #[tokio::test]
    async fn test_real_rust_analyzer_handshake() {
        let temp_dir = TempDir::new().unwrap();
        let root = temp_dir.path();
        fs::write(
            root.join("Cargo.toml"),
            "[package]
name = \"ws\"
version = \"0.1.0\"
edition = \"2021\"
",
        )
        .unwrap();
        fs::create_dir(root.join("src")).unwrap();
        fs::write(
            root.join("src/main.rs"),
            "fn main() {}
",
        )
        .unwrap();

        let server = RustAnalyzerMcpServer::new();
        server
            .initialize_rust_analyzer(root.to_path_buf())
            .await
            .expect("rust-analyzer handshake should succeed");
        assert!(server.analysis_state.read().await.workspace_root.is_some());

        let file = root.join("src/main.rs");
        let hover = server
            .get_hover_info(
                json!({"file_path": file.display().to_string(), "line": 0, "character": 3}),
            )
            .await
            .unwrap();
        assert!(hover.to_string().contains("fn main"), "{hover}");
    }

    #[tokio::test]
    async fn test_analysis_state_update() {
        let server = RustAnalyzerMcpServer::new();
        let test_path = PathBuf::from("/test/path");

        {
            let mut state = server.analysis_state.write().await;
            state.workspace_root = Some(test_path.clone());
            state.file_versions.insert(PathBuf::from("test.rs"), 1);
            state.last_update = Some(Instant::now());
        }

        let state = server.analysis_state.read().await;
        assert_eq!(state.workspace_root, Some(test_path));
        assert_eq!(state.file_versions.get(&PathBuf::from("test.rs")), Some(&1));
        assert!(state.last_update.is_some());
    }
}
