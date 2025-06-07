# Rust Analyzer MCP Server

> **Note**: This project is available at https://github.com/CireSnave/rust-analyzer-mcp-server

A Model Context Protocol (MCP) server that provides Rust language analysis capabilities through rust-analyzer integration. This server enables AI assistants and other MCP clients to access advanced Rust code analysis features.

## Features

- **Diagnostics**: Get compiler errors, warnings, and lints for Rust files
- **Hover Information**: Retrieve type information and documentation for symbols
- **Go to Definition**: Navigate to symbol definitions
- **Find References**: Locate all references to a symbol
- **Code Completions**: Get intelligent code completion suggestions
- **Workspace Analysis**: Analyze entire Rust projects and workspaces

## Requirements

- Rust 1.85.1+
- `rust-analyzer` binary available in PATH
- Windows, macOS, or Linux

## Installation

### Quick One-Line Installation

For the fastest installation, use these one-liners:

**Windows (PowerShell):**
```powershell
git clone https://github.com/CireSnave/rust-analyzer-mcp-server.git && cd rust-analyzer-mcp-server && .\install.ps1
```

**Linux/macOS:**
```bash
git clone https://github.com/CireSnave/rust-analyzer-mcp-server.git && cd rust-analyzer-mcp-server && chmod +x install.sh && ./install.sh
```

### Easy Installation (Recommended)

Choose the installer for your platform:

#### Windows

**Option 1: PowerShell Installer (Recommended)**
```powershell
# Download the repository and run the installer
git clone https://github.com/CireSnave/rust-analyzer-mcp-server.git
cd rust-analyzer-mcp-server

# User installation (recommended)
.\install.ps1

# System-wide installation (requires Administrator)
.\install.ps1 -SystemWide

# Custom directory installation
.\install.ps1 -InstallDir "C:\MyTools"
```

**Option 2: Batch File Installer**
```cmd
# For users who prefer batch files
install.bat

# System-wide installation (requires Administrator)
install.bat --system
```

#### Linux / macOS

**Unix Shell Installer**
```bash
# Download the repository and run the installer
git clone https://github.com/CireSnave/rust-analyzer-mcp-server.git
cd rust-analyzer-mcp-server

# Make installer executable
chmod +x install.sh

# User installation (recommended)
./install.sh

# System-wide installation (requires sudo)
./install.sh --system-wide

# Custom directory installation
./install.sh --install-dir /custom/path
```

#### Universal Quick Install (All Platforms)

**One-liner for cargo users:**
```bash
# If you already have Rust/Cargo installed
git clone https://github.com/CireSnave/rust-analyzer-mcp-server.git
cd rust-analyzer-mcp-server
chmod +x quick-install.sh
./quick-install.sh
```

### What the Installers Do

The installation scripts automatically:

1. ✅ Check for Rust installation (install if missing)
2. ✅ Check for rust-analyzer (install via rustup if missing)  
3. ✅ Build the MCP server from source
4. ✅ Copy binary to appropriate location:
   - **Windows User**: `%LOCALAPPDATA%\RustAnalyzerMCP`
   - **Windows System**: `%ProgramFiles%\RustAnalyzerMCP`
   - **Unix User**: `~/.local/bin`
   - **Unix System**: `/usr/local/bin`
5. ✅ Add installation directory to PATH
6. ✅ Test the installation

### Manual Installation

If you prefer to install manually:

#### From Source

1. Clone the repository:

```bash
git clone https://github.com/CireSnave/rust-analyzer-mcp-server.git
cd rust-analyzer-mcp-server
```

2. Build the project:

```bash
cargo build --release
```

3. The binary will be available at `./target/release/rust-analyzer-mcp-server` (or `.exe` on Windows)

4. Copy to your preferred location and add to PATH

#### Pre-built Binaries

Download the latest release from the [releases page](https://github.com/CireSnave/rust-analyzer-mcp-server/releases).

### Verification

After installation, verify it works:

```bash
# Check version
rust-analyzer-mcp-server --version

# Show help
rust-analyzer-mcp-server --help

# Test with current directory
rust-analyzer-mcp-server .

## Uninstallation

### Easy Uninstallation

If you need to remove the MCP server, use the provided uninstallers:

#### Windows

**PowerShell Uninstaller:**
```powershell
# Remove user installation
.\uninstall.ps1

# Remove system-wide installation (requires Administrator)
.\uninstall.ps1 -SystemWide

# Remove from custom directory
.\uninstall.ps1 -InstallDir "C:\MyTools"

# Skip confirmation prompts
.\uninstall.ps1 -Force
```

**Batch Uninstaller:**
```cmd
# Remove user installation
uninstall.bat

# Remove system-wide installation (requires Administrator)
uninstall.bat --system

# Skip confirmation prompts
uninstall.bat --force
```

#### Linux / macOS

**Unix Shell Uninstaller:**
```bash
# Remove user installation
./uninstall.sh

# Remove system-wide installation (requires sudo)
./uninstall.sh --system-wide

# Remove from custom directory
./uninstall.sh --install-dir /custom/path

# Skip confirmation prompts
./uninstall.sh --force
```

#### Universal Quick Uninstall

**One-liner for all platforms:**
```bash
# Automatically finds and removes all installations
chmod +x quick-uninstall.sh
./quick-uninstall.sh
```

### What the Uninstallers Do

The uninstallation scripts automatically:

1. ✅ Find the MCP server installation (checks common locations)
2. ✅ Stop any running MCP server processes
3. ✅ Remove the binary and installation directory
4. ✅ Clean up PATH environment variable entries
5. ✅ Provide confirmation prompts (unless `--force` is used)
6. ✅ Create backups of modified configuration files

**Note**: The uninstallers do NOT remove Rust or rust-analyzer, as these may be used by other projects.

## Available Files

This project includes the following installation and management scripts:

### Installation Scripts
- **`install.ps1`** - Windows PowerShell installer (recommended for Windows)
- **`install.bat`** - Windows Batch installer (alternative for Windows)
- **`install.sh`** - Unix shell installer for Linux/macOS
- **`quick-install.sh`** - Universal installer for all platforms (requires Cargo)

### Uninstallation Scripts
- **`uninstall.ps1`** - Windows PowerShell uninstaller
- **`uninstall.bat`** - Windows Batch uninstaller
- **`uninstall.sh`** - Unix shell uninstaller for Linux/macOS
- **`quick-uninstall.sh`** - Universal uninstaller for all platforms

### Quick Reference

**Install:**
- Windows: `.\install.ps1`
- Linux/macOS: `./install.sh`
- Any platform: `./quick-install.sh`

**Uninstall:**
- Windows: `.\uninstall.ps1`
- Linux/macOS: `./uninstall.sh`
- Any platform: `./quick-uninstall.sh`

All scripts include `--help` options for detailed usage information.

## Usage

### Command Line

```bash
# Show help
./rust-analyzer-mcp-server --help

# Run with current directory as workspace
./rust-analyzer-mcp-server

# Run with specific workspace
./rust-analyzer-mcp-server /path/to/rust/project
```

### Available Tools

The server exposes the following MCP tools:

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_diagnostics` | Get diagnostics for a Rust file | `file_path`: Path to the Rust file |
| `get_hover_info` | Get hover information for a symbol | `file_path`: Path to file, `line`: Line number, `character`: Character position |
| `goto_definition` | Go to definition of a symbol | `file_path`: Path to file, `line`: Line number, `character`: Character position |
| `find_references` | Find all references to a symbol | `file_path`: Path to file, `line`: Line number, `character`: Character position |
| `get_completions` | Get code completions | `file_path`: Path to file, `line`: Line number, `character`: Character position |
| `analyze_workspace` | Analyze the entire workspace | None |

## MCP Client Integration

### GitHub Copilot in VS Code

1. **Install the MCP extension for VS Code** (if available) or configure manually:

2. **Add to VS Code settings** (`settings.json`):

```json
{
  "mcp.servers": {
    "rust-analyzer-mcp": {
      "command": "/path/to/rust-analyzer-mcp-server",
      "args": ["${workspaceFolder}"],
      "env": {}
    }
  }
}
```

3. **Alternative: Use with GitHub Copilot Chat**:
   - Open a Rust project in VS Code
   - Start the MCP server manually in a terminal:

     ```bash
     ./rust-analyzer-mcp-server .
     ```

   - The server will be available for MCP-compatible tools

### Claude Desktop

1. **Add to Claude Desktop configuration** (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "rust-analyzer": {
      "command": "/path/to/rust-analyzer-mcp-server",
      "args": ["/path/to/your/rust/project"]
    }
  }
}
```

2. **Location of config file**:
   - **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
   - **Linux**: `~/.config/Claude/claude_desktop_config.json`

### Other MCP Clients

For other MCP-compatible clients, configure them to run:

```bash
/path/to/rust-analyzer-mcp-server [workspace-path]
```

The server communicates via JSON-RPC over stdin/stdout following the MCP protocol specification.

## Configuration

### Environment Variables

- `RUST_LOG`: Set logging level (e.g., `debug`, `info`, `warn`, `error`)
- `RUST_ANALYZER_PATH`: Custom path to rust-analyzer binary (if not in PATH)

### Workspace Setup

For best results:

1. Ensure your Rust project has a `Cargo.toml` file
2. Run `cargo check` at least once to populate the target directory
3. Make sure `rust-analyzer` can find your dependencies

## Protocol Details

This server implements the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) specification. It accepts JSON-RPC requests over stdin and returns responses over stdout.

### Example Request

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_diagnostics",
    "arguments": {
      "file_path": "/path/to/file.rs"
    }
  }
}
```

### Example Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Found 2 diagnostics:\n1. Error at line 5: expected `;`\n2. Warning at line 10: unused variable `x`"
      }
    ]
  }
}
```

## Troubleshooting

### Common Issues

1. **rust-analyzer not found**:
   - Ensure `rust-analyzer` is installed and in PATH
   - Set `RUST_ANALYZER_PATH` environment variable if needed

2. **Project not analyzed**:
   - Make sure you're in a Rust project directory
   - Check that `Cargo.toml` exists
   - Run `cargo check` to ensure project builds

3. **Permission errors**:
   - Ensure the binary has execute permissions
   - Check file paths are accessible

### Debug Mode

Run with debug logging:

```bash
RUST_LOG=debug ./rust-analyzer-mcp-server /path/to/project
```

## Development

### Building from Source

```bash
# Debug build
cargo build

# Release build
cargo build --release

# Run tests
cargo test

# Check code quality
cargo clippy
cargo fmt
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run `cargo test` and `cargo clippy`
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [rust-analyzer](https://github.com/rust-lang/rust-analyzer) for providing the language server
- [Model Context Protocol](https://modelcontextprotocol.io/) for the protocol specification
- [tower-lsp](https://github.com/ebkalderon/tower-lsp) for LSP client implementation

## Support

- Create an issue on GitHub for bugs or feature requests
- Check existing issues for common problems
- Consult the MCP specification for protocol details
