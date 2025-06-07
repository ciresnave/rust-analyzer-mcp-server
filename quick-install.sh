#!/usr/bin/env bash
# Rust Analyzer MCP Server - Universal Quick Installer
# This script works on Windows (Git Bash/WSL), Linux, and macOS

set -e

# Parse command line arguments
AUTO_START=false
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-start)
            AUTO_START=true
            shift
            ;;
        --help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    cat << EOF
Rust Analyzer MCP Server - Universal Quick Installer

Usage:
  ./quick-install.sh                 # Install using cargo
  ./quick-install.sh --auto-start    # Install and enable auto-start at boot

Options:
  --auto-start    Enable auto-start at system boot
  --help         Show this help message

This installer uses 'cargo install' and works on all platforms with Rust installed.

EOF
    exit 0
fi

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    PURPLE='\033[0;35m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' PURPLE='' NC=''
fi

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }
print_header() { echo -e "${PURPLE}=== $1 ===${NC}"; }

# Detect OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)     OS_NAME="linux";;
    Darwin*)    OS_NAME="macos";;
    CYGWIN*|MINGW*|MSYS*) OS_NAME="windows";;
    *)          print_error "Unsupported OS: $OS"; exit 1;;
esac

case "$ARCH" in
    x86_64|amd64)   ARCH_NAME="x86_64";;
    arm64|aarch64)  ARCH_NAME="aarch64";;
    *)              print_error "Unsupported architecture: $ARCH"; exit 1;;
esac

print_header "Rust Analyzer MCP Server - Quick Installer"
print_info "Detected platform: $OS_NAME-$ARCH_NAME"
echo

# Check for curl or wget
if command -v curl &> /dev/null; then
    DOWNLOADER="curl -fsSL"
elif command -v wget &> /dev/null; then
    DOWNLOADER="wget -qO-"
else
    print_error "Neither curl nor wget found. Please install one of them."
    exit 1
fi

# Installation function using cargo
install_with_cargo() {
    print_info "Installing via cargo from source..."
    
    # Check if Rust is installed
    if ! command -v cargo &> /dev/null; then
        print_error "Rust/Cargo not found. Installing Rust..."
        
        # Install Rust
        if command -v curl &> /dev/null; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        else
            print_error "Please install Rust manually from https://rustup.rs/"
            exit 1
        fi
        
        # Source the environment
        source "$HOME/.cargo/env" 2>/dev/null || true
        export PATH="$HOME/.cargo/bin:$PATH"
        
        if ! command -v cargo &> /dev/null; then
            print_error "Failed to install Rust. Please install manually from https://rustup.rs/"
            exit 1
        fi
        
        print_success "Rust installed successfully"
    fi
    
    # Install rust-analyzer if not present
    if ! command -v rust-analyzer &> /dev/null; then
        print_info "Installing rust-analyzer..."
        rustup component add rust-analyzer || {
            print_warning "Failed to install rust-analyzer via rustup. Continuing anyway..."
        }
    fi
    
    # Install the MCP server
    print_info "Installing rust-analyzer-mcp-server via cargo..."
    
    # Create a temporary directory and install from source
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    cd "$TEMP_DIR"
    
    # Clone or download source (for now, we'll install from local source)
    # In a real scenario, you'd clone from git or download a release
    print_info "Building from current directory..."
    cd - > /dev/null
    
    cargo install --path . --force
    
    if command -v rust-analyzer-mcp-server &> /dev/null; then
        print_success "Installation completed successfully!"
        VERSION=$(rust-analyzer-mcp-server --version)
        print_info "Installed version: $VERSION"
        
        # Install uninstaller
        CARGO_BIN_DIR="$HOME/.cargo/bin"
        if [ -f "uninstall.sh" ]; then
            cp "uninstall.sh" "$CARGO_BIN_DIR/rust-analyzer-mcp-server-uninstall.sh"
            chmod +x "$CARGO_BIN_DIR/rust-analyzer-mcp-server-uninstall.sh"
            print_success "Uninstaller installed: $CARGO_BIN_DIR/rust-analyzer-mcp-server-uninstall.sh"
        fi
        
    else
        print_error "Installation failed - binary not found in PATH"
        print_info "You may need to add ~/.cargo/bin to your PATH"
        print_info "Add this to your shell profile: export PATH=\"\$HOME/.cargo/bin:\$PATH\""
        exit 1
    fi
}

# Main installation
print_info "Starting installation..."
install_with_cargo

# Set up auto-start if requested
if [ "$AUTO_START" = true ]; then
    print_info "Setting up auto-start at system boot..."
    BINARY_PATH=$(which rust-analyzer-mcp-server)
    
    if command -v systemctl > /dev/null 2>&1; then
        # Linux with systemd (user service)
        USER_SERVICE_DIR="$HOME/.config/systemd/user"
        mkdir -p "$USER_SERVICE_DIR"
        SERVICE_FILE="$USER_SERVICE_DIR/rust-analyzer-mcp-server.service"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rust Analyzer MCP Server
After=graphical-session.target

[Service]
Type=simple
ExecStart=$BINARY_PATH %h
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable rust-analyzer-mcp-server.service
        print_success "Auto-start configured (systemd user service)"
    elif [ "$(uname)" = "Darwin" ]; then
        # macOS user auto-start
        USER_AGENTS_DIR="$HOME/Library/LaunchAgents"
        mkdir -p "$USER_AGENTS_DIR"
        PLIST_FILE="$USER_AGENTS_DIR/com.rust-analyzer-mcp-server.plist"
        cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rust-analyzer-mcp-server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
        <string>$HOME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
        launchctl load "$PLIST_FILE"
        print_success "Auto-start configured (launchd user)"
    else
        # Fallback: add to shell profile
        SHELL_RC=""
        if [ -f "$HOME/.bashrc" ]; then
            SHELL_RC="$HOME/.bashrc"
        elif [ -f "$HOME/.zshrc" ]; then
            SHELL_RC="$HOME/.zshrc"
        elif [ -f "$HOME/.profile" ]; then
            SHELL_RC="$HOME/.profile"
        fi
        
        if [ -n "$SHELL_RC" ]; then
            echo "" >> "$SHELL_RC"
            echo "# Auto-start Rust Analyzer MCP Server" >> "$SHELL_RC"
            echo "$BINARY_PATH \$HOME &" >> "$SHELL_RC"
            print_success "Auto-start configured (shell profile): $SHELL_RC"
        else
            print_warning "Could not set up auto-start: no suitable method found"
        fi
    fi
fi

echo
print_header "Installation Complete"
echo
print_success "Rust Analyzer MCP Server is now installed!"
print_info "Usage: rust-analyzer-mcp-server --help"
print_info "Location: $(which rust-analyzer-mcp-server 2>/dev/null || echo 'In ~/.cargo/bin')"
print_info "Uninstaller: $(dirname "$(which rust-analyzer-mcp-server 2>/dev/null)")/rust-analyzer-mcp-server-uninstall.sh"

if [ "$AUTO_START" = true ]; then
    print_info "Auto-start at boot: Enabled"
fi

echo
print_info "Quick start:"
print_info "  1. Navigate to a Rust project directory"
print_info "  2. Run: rust-analyzer-mcp-server ."
print_info "  3. The server will start and wait for MCP client connections"
echo
print_info "For MCP client configuration (VS Code, Claude, etc.), see README.md"
