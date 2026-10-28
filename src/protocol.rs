use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Handshake-based ("legacy") MCP revisions this server speaks, oldest first.
/// It only uses `initialize`, `tools/list` and `tools/call`, which these share.
const SUPPORTED_PROTOCOL_VERSIONS: [&str; 4] =
    ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"];

/// The stateless MCP revision: no handshake, the version rides on every
/// request in `_meta`, and `server/discover` reports what the server speaks.
pub(crate) const MODERN_PROTOCOL_VERSION: &str = "2026-07-28";

const VERSION_META_KEY: &str = "io.modelcontextprotocol/protocolVersion";
const SERVER_INFO_META_KEY: &str = "io.modelcontextprotocol/serverInfo";

/// JSON-RPC code of `UnsupportedProtocolVersionError`.
pub(crate) const UNSUPPORTED_PROTOCOL_VERSION: i64 = -32022;

/// The protocol version a request declares in `params._meta`, if any. A
/// request that declares one is served statelessly; one that does not is a
/// legacy-era request.
pub(crate) fn requested_modern_version(params: Option<&Value>) -> Option<&str> {
    params?.get("_meta")?.get(VERSION_META_KEY)?.as_str()
}

/// Every version we speak, newest first.
fn all_supported_versions() -> Vec<&'static str> {
    std::iter::once(MODERN_PROTOCOL_VERSION)
        .chain(SUPPORTED_PROTOCOL_VERSIONS.iter().rev().copied())
        .collect()
}

pub(crate) fn unsupported_version_error(requested: &str) -> McpError {
    McpError {
        code: UNSUPPORTED_PROTOCOL_VERSION,
        message: "Unsupported protocol version".to_string(),
        data: Some(serde_json::json!({
            "supported": all_supported_versions(),
            "requested": requested,
        })),
    }
}

/// Result of `server/discover`.
pub(crate) fn discover_result() -> Value {
    serde_json::json!({
        "resultType": "complete",
        "supportedVersions": all_supported_versions(),
        "capabilities": {"tools": {}},
        "_meta": {
            SERVER_INFO_META_KEY: {
                "name": "rust-analyzer-mcp-server",
                "version": env!("CARGO_PKG_VERSION")
            }
        },
        "instructions": "Rust code intelligence from rust-analyzer: diagnostics, hover, definition, references and completions for a workspace. Positions are 0-based line and character. The first call can be slow while rust-analyzer loads the project.",
        "ttlMs": 3_600_000,
        "cacheScope": "public"
    })
}

/// Modern-era results carry `resultType`.
pub(crate) fn mark_complete(mut result: Value) -> Value {
    if let Some(obj) = result.as_object_mut() {
        obj.entry("resultType").or_insert(Value::from("complete"));
    }
    result
}

/// Echo the client's requested version when supported, else offer our newest.
pub(crate) fn negotiate_protocol_version(params: Option<&Value>) -> &'static str {
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

impl McpResponse {
    pub(crate) fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub(crate) fn failure(id: Option<Value>, error: McpError) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: None,
            error: Some(error),
        }
    }
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
