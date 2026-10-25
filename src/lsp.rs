use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Child;
use tokio::sync::{Mutex, RwLock};
use tower_lsp::lsp_types::*;

// LSP Protocol types
#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct LspRequest {
    jsonrpc: String,
    id: i64,
    method: String,
    params: Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct LspNotification {
    jsonrpc: String,
    method: String,
    params: Value,
}

// Analysis state for tracking workspace information
#[derive(Debug, Clone)]
pub struct AnalysisState {
    pub last_update: Option<Instant>,
    pub file_versions: HashMap<PathBuf, u64>,
    pub diagnostics: HashMap<PathBuf, Vec<Diagnostic>>,
    pub workspace_root: Option<PathBuf>,
    /// rust-analyzer finished loading/indexing (experimental/serverStatus).
    pub quiescent: bool,
}

// LSP Client for communicating with rust-analyzer
pub struct LspClient {
    pub(crate) stdin: Arc<Mutex<tokio::process::ChildStdin>>,
    pub(crate) request_id: Arc<Mutex<i64>>,
    pub(crate) pending_requests: PendingRequests,
    pub(crate) _child: Child,
}

pub(crate) type PendingRequests =
    Arc<RwLock<HashMap<i64, tokio::sync::oneshot::Sender<std::result::Result<Value, String>>>>>;

pub(crate) fn path_to_uri(path: &Path) -> Result<Url> {
    let abs = std::path::absolute(path)?;
    Url::from_file_path(&abs).map_err(|_| anyhow!("Cannot convert {} to a file URI", abs.display()))
}

/// Key for the diagnostics map. rust-analyzer may report `c:/x` for a file we
/// opened as `C:/x`, so compare Windows paths case-insensitively.
pub(crate) fn diag_key(path: &Path) -> PathBuf {
    if cfg!(windows) {
        PathBuf::from(path.to_string_lossy().to_lowercase())
    } else {
        path.to_path_buf()
    }
}

/// Read LSP messages from rust-analyzer's stdout until it closes.
/// Responses resolve pending requests, `publishDiagnostics` is stored in the
/// analysis state, and server-to-client requests get a null reply.
pub(crate) async fn lsp_reader(
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

impl LspClient {
    pub(crate) async fn send_request(&self, method: &str, params: Value) -> Result<Value> {
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

    pub(crate) async fn send_notification(&self, method: &str, params: Value) -> Result<()> {
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
