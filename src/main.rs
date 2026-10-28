mod lsp;
mod protocol;
mod server;

use anyhow::Result;
use clap::Arg;
use protocol::{McpError, McpRequest, McpResponse};
use server::RustAnalyzerMcpServer;
use std::path::{Path, PathBuf};
use tokio::io::{AsyncBufReadExt, BufReader};

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
