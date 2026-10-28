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
        .get_hover_info(json!({"file_path": file.display().to_string(), "line": 0, "character": 3}))
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
