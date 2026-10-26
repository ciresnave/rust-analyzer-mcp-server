use crate::lsp::*;
use crate::protocol::*;
use anyhow::{Result, anyhow};
use notify::{Event, EventKind, RecursiveMode, Watcher};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::process::Command;
use tokio::sync::{Mutex, RwLock, mpsc};
use tower_lsp::lsp_types::*;

/// MCP tool result carrying a single text block.
fn text_result(text: String) -> Value {
    json!({"content": [{"type": "text", "text": text}]})
}

fn tool(name: &str, description: &str, input_schema: Value) -> ToolDefinition {
    ToolDefinition {
        name: name.to_string(),
        description: description.to_string(),
        input_schema,
    }
}

fn position_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "file_path": {"type": "string"},
            "line": {"type": "integer"},
            "character": {"type": "integer"}
        },
        "required": ["file_path", "line", "character"]
    })
}

/// Directories `analyze_workspace` does not descend into.
fn is_skipped_dir(name: &str) -> bool {
    name == "target" || name.starts_with('.')
}

pub(crate) fn is_rust_file(path: &Path) -> bool {
    path.extension().is_some_and(|ext| ext == "rs")
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
                last_update: None,
                file_versions: HashMap::new(),
                diagnostics: HashMap::new(),
                workspace_root: None,
                quiescent: false,
            })),
            file_watcher: Arc::new(Mutex::new(None)),
        }
    }

    /// Spawn rust-analyzer and the task that reads its replies.
    fn spawn_lsp_client(&self) -> Result<LspClient> {
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

        Ok(LspClient {
            stdin,
            request_id: Arc::new(Mutex::new(1)),
            pending_requests: pending,
            _child: child,
        })
    }

    pub async fn initialize_rust_analyzer(&self, workspace_root: PathBuf) -> Result<()> {
        let workspace_root = std::path::absolute(&workspace_root)?;
        let lsp_client = self.spawn_lsp_client()?;

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

        self.analysis_state.write().await.workspace_root = Some(workspace_root.clone());
        *self.lsp_client.write().await = Some(lsp_client);

        self.start_file_watcher(workspace_root).await?;

        Ok(())
    }

    fn make_watcher(tx: mpsc::Sender<Event>) -> Result<notify::RecommendedWatcher> {
        Ok(notify::recommended_watcher(
            move |res: notify::Result<Event>| {
                if let Ok(event) = res {
                    if tx.blocking_send(event).is_err() {
                        eprintln!("Failed to send file event");
                    }
                }
            },
        )?)
    }

    /// Resync every changed `.rs` file named by a filesystem event.
    async fn sync_event_paths(
        event: &Event,
        lsp_client: &Arc<RwLock<Option<LspClient>>>,
        analysis_state: &Arc<RwLock<AnalysisState>>,
    ) {
        if !matches!(
            event.kind,
            EventKind::Modify(_) | EventKind::Create(_) | EventKind::Remove(_)
        ) {
            return;
        }
        for path in event.paths.iter().filter(|p| is_rust_file(p)) {
            if let Some(client) = lsp_client.read().await.as_ref() {
                let _ = Self::handle_file_change(client, path, analysis_state).await;
            }
        }
    }

    async fn start_file_watcher(&self, workspace_root: PathBuf) -> Result<()> {
        let analysis_state = self.analysis_state.clone();
        let lsp_client = self.lsp_client.clone();

        let (tx, mut rx) = mpsc::channel(100);
        let mut watcher = Self::make_watcher(tx)?;
        watcher.watch(&workspace_root, RecursiveMode::Recursive)?;
        *self.file_watcher.lock().await = Some(watcher);

        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                Self::sync_event_paths(&event, &lsp_client, &analysis_state).await;
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
            tool(
                "get_diagnostics",
                "Get diagnostics for a Rust file",
                json!({
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "Path to the Rust file"
                        }
                    },
                    "required": ["file_path"]
                }),
            ),
            tool(
                "get_hover_info",
                "Get hover information for a symbol at a specific position",
                position_schema(),
            ),
            tool(
                "goto_definition",
                "Go to definition of a symbol",
                position_schema(),
            ),
            tool(
                "find_references",
                "Find all references to a symbol",
                position_schema(),
            ),
            tool(
                "get_completions",
                "Get code completions at a specific position",
                position_schema(),
            ),
            tool(
                "analyze_workspace",
                "Analyze the entire workspace for issues",
                json!({
                    "type": "object",
                    "properties": {},
                    "additionalProperties": false
                }),
            ),
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

        let diagnostics = self.wait_for_diagnostics(client, file_path, &key).await?;
        Ok(text_result(format!(
            "Diagnostics for {}: {}",
            file_path,
            serde_json::to_string(&diagnostics)?
        )))
    }

    /// rust-analyzer pushes diagnostics asynchronously; wait for them.
    async fn wait_for_diagnostics(
        &self,
        client: &LspClient,
        file_path: &str,
        key: &Path,
    ) -> Result<Vec<Diagnostic>> {
        let deadline = Instant::now() + Duration::from_secs(90);
        let mut resynced = false;
        loop {
            let quiescent = self.analysis_state.read().await.quiescent;
            if quiescent && !resynced {
                // Anything published while the project was still loading is
                // incomplete: ask again now that analysis can see everything.
                resynced = true;
                self.analysis_state.write().await.diagnostics.remove(key);
                self.open_document(client, file_path).await?;
            } else if quiescent {
                if let Some(d) = self.analysis_state.read().await.diagnostics.get(key) {
                    return Ok(d.clone());
                }
            }
            if Instant::now() >= deadline {
                return Err(anyhow!("Timed out waiting for diagnostics for {file_path}"));
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
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

    /// Shared body of the position-based tools: validate arguments, wait for
    /// rust-analyzer, sync the file, send `method`, and label the reply.
    async fn position_request(
        &self,
        args: Value,
        method: &str,
        label: &str,
        context: Option<Value>,
    ) -> Result<Value> {
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
        let mut params = json!({
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": character}
        });
        if let Some(context) = context {
            params["context"] = context;
        }

        let response = client.send_request(method, params).await?;
        Ok(text_result(format!("{label}: {response}")))
    }

    async fn get_hover_info(&self, args: Value) -> Result<Value> {
        self.position_request(args, "textDocument/hover", "Hover info", None)
            .await
    }

    async fn goto_definition(&self, args: Value) -> Result<Value> {
        self.position_request(args, "textDocument/definition", "Definition", None)
            .await
    }

    async fn find_references(&self, args: Value) -> Result<Value> {
        let context = json!({"includeDeclaration": true});
        self.position_request(args, "textDocument/references", "References", Some(context))
            .await
    }

    async fn get_completions(&self, args: Value) -> Result<Value> {
        self.position_request(args, "textDocument/completion", "Completions", None)
            .await
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

#[cfg(test)]
mod tests;
