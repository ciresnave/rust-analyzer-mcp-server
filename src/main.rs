use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, RwLock, Mutex};
use tokio::process::{Command, Child};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use notify::{Watcher, RecursiveMode, Event, EventKind};
use serde_json::{json, Value};
use serde::{Deserialize, Serialize};
use tower_lsp::lsp_types::*;
use anyhow::{Result, anyhow};
use clap::Arg;

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
struct LspResponse {
    jsonrpc: String,
    id: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<LspError>,
}

#[derive(Debug, Serialize, Deserialize)]
struct LspError {
    code: i64,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<Value>,
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
}

// LSP Client for communicating with rust-analyzer
pub struct LspClient {
    stdin: Arc<Mutex<tokio::process::ChildStdin>>,
    request_id: Arc<Mutex<i64>>,
    pending_requests: Arc<RwLock<HashMap<i64, tokio::sync::oneshot::Sender<Value>>>>,
    _child: Child,
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
            })),
            file_watcher: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn initialize_rust_analyzer(&self, workspace_root: PathBuf) -> Result<()> {
        let mut child = Command::new("rust-analyzer")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        let stdin = child.stdin.take().ok_or_else(|| anyhow!("Failed to open stdin"))?;
        let _stdout = child.stdout.take().ok_or_else(|| anyhow!("Failed to open stdout"))?;

        let lsp_client = LspClient {
            stdin: Arc::new(Mutex::new(stdin)),
            request_id: Arc::new(Mutex::new(1)),
            pending_requests: Arc::new(RwLock::new(HashMap::new())),
            _child: child,
        };

        // Initialize LSP
        let initialize_params = json!({
            "processId": null,
            "rootPath": workspace_root,
            "rootUri": format!("file://{}", workspace_root.display()),
            "capabilities": {},
            "workspaceFolders": [{
                "uri": format!("file://{}", workspace_root.display()),
                "name": workspace_root.file_name().unwrap_or_default().to_string_lossy()
            }]
        });

        let lsp_client_mut = lsp_client;
        lsp_client_mut.send_request("initialize", initialize_params).await?;
        lsp_client_mut.send_notification("initialized", json!({})).await?;

        // Update state
        {
            let mut state = self.analysis_state.write().await;
            state.workspace_root = Some(workspace_root.clone());
        }

        *self.lsp_client.write().await = Some(lsp_client_mut);

        // Start file watcher
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
                if let EventKind::Modify(_) | EventKind::Create(_) | EventKind::Remove(_) = event.kind {
                    for path in &event.paths {
                        if path.extension().is_some_and(|ext| ext == "rs") {
                            // Notify LSP about file changes
                            if let Some(client) = lsp_client.read().await.as_ref() {
                                let _ = Self::handle_file_change(client, path, &analysis_state).await;
                            }
                        }
                    }
                }
            }
        });

        Ok(())
    }

    async fn handle_file_change(
        client: &LspClient,
        path: &Path,
        analysis_state: &Arc<RwLock<AnalysisState>>,
    ) -> Result<()> {
        let uri = format!("file://{}", path.display());
        let content = tokio::fs::read_to_string(path).await.unwrap_or_default();

        // Send didOpen or didChange notification
        let params = json!({
            "textDocument": {
                "uri": uri,
                "languageId": "rust",
                "version": 1,
                "text": content
            }
        });

        client.send_notification("textDocument/didOpen", params).await?;

        // Update file version
        {
            let mut state = analysis_state.write().await;
            state.file_versions.insert(path.to_path_buf(), 1);
            state.last_update = Some(Instant::now());
        }

        Ok(())
    }

    pub async fn handle_mcp_request(&self, request: McpRequest) -> Result<McpResponse> {
        let result = match request.method.as_str() {
            "tools/list" => self.list_tools().await,
            "tools/call" => self.call_tool(request.params).await,
            "initialize" => Ok(json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "rust-analyzer-mcp-server",
                    "version": "0.1.0"
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
                description: "Get hover information for a symbol at a specific position".to_string(),
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
        let tool_name = params["name"].as_str().ok_or_else(|| anyhow!("No tool name provided"))?;
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
        let file_path = args["file_path"].as_str().ok_or_else(|| anyhow!("file_path required"))?;
        let client_guard = self.lsp_client.read().await;
        let client = client_guard.as_ref().ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = format!("file://{file_path}");
        let params = json!({
            "textDocument": {
                "uri": uri
            }
        });

        let response = client.send_request("textDocument/publishDiagnostics", params).await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Diagnostics for {}: {}", file_path, response)
            }]
        }))
    }

    async fn get_hover_info(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"].as_str().ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"].as_u64().ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"].as_u64().ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard.as_ref().ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = format!("file://{file_path}");
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
        let file_path = args["file_path"].as_str().ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"].as_u64().ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"].as_u64().ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard.as_ref().ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = format!("file://{file_path}");
        let params = json!({
            "textDocument": {
                "uri": uri
            },
            "position": {
                "line": line,
                "character": character
            }
        });

        let response = client.send_request("textDocument/definition", params).await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Definition: {}", response)
            }]
        }))
    }

    async fn find_references(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"].as_str().ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"].as_u64().ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"].as_u64().ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard.as_ref().ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = format!("file://{file_path}");
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

        let response = client.send_request("textDocument/references", params).await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("References: {}", response)
            }]
        }))
    }

    async fn get_completions(&self, args: Value) -> Result<Value> {
        let file_path = args["file_path"].as_str().ok_or_else(|| anyhow!("file_path required"))?;
        let line = args["line"].as_u64().ok_or_else(|| anyhow!("line required"))? as u32;
        let character = args["character"].as_u64().ok_or_else(|| anyhow!("character required"))? as u32;

        let client_guard = self.lsp_client.read().await;
        let client = client_guard.as_ref().ok_or_else(|| anyhow!("LSP client not initialized"))?;

        let uri = format!("file://{file_path}");
        let params = json!({
            "textDocument": {
                "uri": uri
            },
            "position": {
                "line": line,
                "character": character
            }
        });

        let response = client.send_request("textDocument/completion", params).await?;
        Ok(json!({
            "content": [{
                "type": "text",
                "text": format!("Completions: {}", response)
            }]
        }))
    }

    async fn analyze_workspace(&self) -> Result<Value> {
        let state = self.analysis_state.read().await;
        let workspace_root = state.workspace_root.as_ref()
            .ok_or_else(|| anyhow!("Workspace not initialized"))?;

        let mut analysis_results = Vec::new();
        
        // Get all Rust files in workspace
        let rust_files = Self::find_rust_files(workspace_root).await?;
        
        for file in rust_files {
            if let Ok(diagnostics) = self.get_diagnostics(json!({"file_path": file.display().to_string()})).await {
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

    fn find_rust_files(dir: &Path) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Vec<PathBuf>>> + Send + '_>> {
        Box::pin(async move {
            let mut rust_files = Vec::new();
            let mut entries = tokio::fs::read_dir(dir).await?;

            while let Some(entry) = entries.next_entry().await? {
                let path = entry.path();
                if path.is_dir() {
                    if let Ok(mut sub_files) = Self::find_rust_files(&path).await {
                        rust_files.append(&mut sub_files);
                    }
                } else if path.extension().is_some_and(|ext| ext == "rs") {
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
        let message = format!("Content-Length: {}\r\n\r\n{}", request_json.len(), request_json);

        // Create a channel for the response
        let (tx, rx) = tokio::sync::oneshot::channel();
        {
            let mut pending = self.pending_requests.write().await;
            pending.insert(id, tx);
        }

        // Send the request
        let mut stdin = self.stdin.lock().await;
        stdin.write_all(message.as_bytes()).await?;
        stdin.flush().await?;

        // Wait for response with timeout
        let response = tokio::time::timeout(Duration::from_secs(10), rx).await??;
        Ok(response)
    }

    async fn send_notification(&self, method: &str, params: Value) -> Result<()> {
        let notification = LspNotification {
            jsonrpc: "2.0".to_string(),
            method: method.to_string(),
            params,
        };

        let notification_json = serde_json::to_string(&notification)?;
        let message = format!("Content-Length: {}\r\n\r\n{}", notification_json.len(), notification_json);

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
        .version("0.1.0")
        .about("🦀 MCP Server for rust-analyzer integration")
        .author("CireSnave")
        .arg(
            Arg::new("workspace")
                .help("Workspace root directory")
                .value_name("WORKSPACE")
                .index(1)
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
    println!();
    println!("╔══════════════════════════════════════════════════════════════╗");
    println!("║            🦀 Rust Analyzer MCP Server v0.1.0               ║");
    println!("╚══════════════════════════════════════════════════════════════╝");
    println!();
    println!("🚀 Starting MCP server for workspace: {}", workspace_root.display());
    println!();
    println!("🛠️  Available Tools:");
    println!("  📊 get_diagnostics     Get diagnostics for a Rust file");
    println!("  💡 get_hover_info       Get hover information for a symbol");
    println!("  🎯 goto_definition      Go to definition of a symbol");
    println!("  🔍 find_references      Find all references to a symbol");
    println!("  ✨ get_completions      Get code completions");
    println!("  🔬 analyze_workspace    Analyze the entire workspace");
    println!();
    println!("📡 MCP Protocol: Ready for client connections");
    println!("💻 Listening on stdin/stdout for MCP requests...");
    println!();
}

fn print_initialization_error(error: &anyhow::Error) {
    println!("⚠️  Warning: Failed to initialize rust-analyzer");
    println!("   Error: {}", error);
    println!("   The MCP server will run with limited functionality");
    println!("   Please ensure rust-analyzer is installed and accessible");
    println!();
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
    if let Err(e) = server.initialize_rust_analyzer(workspace_root.clone()).await {
        print_initialization_error(&e);
    } else {
        println!("✅ rust-analyzer initialized successfully");
        println!();
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
                    let response = server.handle_mcp_request(request).await.unwrap_or_else(|e| {
                        McpResponse {
                            jsonrpc: "2.0".to_string(),
                            id: None,
                            result: None,
                            error: Some(McpError {
                                code: -32603,
                                message: e.to_string(),
                                data: None,
                            }),
                        }
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
    use tempfile::TempDir;
    use std::fs;

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
        
        let tool_names: Vec<&str> = tools
            .iter()
            .map(|t| t["name"].as_str().unwrap())
            .collect();
        
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
        assert_eq!(result["protocolVersion"], "2024-11-05");
        assert!(result["capabilities"]["tools"].is_object());
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

        let rust_files = RustAnalyzerMcpServer::find_rust_files(temp_path).await.unwrap();
        
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
