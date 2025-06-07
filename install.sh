#!/bin/bash
# Rust Analyzer MCP Server - Unix Installer (Linux/macOS)
# Enhanced with automatic MCP client detection and configuration

set -e

# Default values
SYSTEM_WIDE=false
INSTALL_DIR=""
AUTO_START=false
CONFIGURE_MCP=true
SHOW_HELP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --system-wide)
            SYSTEM_WIDE=true
            shift
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --auto-start)
            AUTO_START=true
            shift
            ;;
        --no-configure-mcp)
            CONFIGURE_MCP=false
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
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║              🦀 Rust Analyzer MCP Server Installer          ║
╚══════════════════════════════════════════════════════════════╝

🚀 Usage:
  ./install.sh                               # Install to user directory
  ./install.sh --system-wide                 # Install system-wide (requires sudo)
  ./install.sh --install-dir /custom/path    # Install to custom directory
  ./install.sh --auto-start                  # Install and enable auto-start at boot
  ./install.sh --no-configure-mcp            # Skip automatic MCP client configuration

⚙️  Options:
  --system-wide       Install system-wide (requires sudo)
  --install-dir       Specify custom installation directory
  --auto-start        Enable auto-start at system boot
  --no-configure-mcp  Skip automatic MCP client configuration
  --help              Show this help message

🔍 This installer will automatically detect and configure:
   • GitHub Copilot in VS Code
   • Claude Desktop
   • Cursor
   • Other MCP-compatible clients

EOF
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_header() {
    echo
    local len=${#1}
    echo -e "${PURPLE}╔$(printf '═%.0s' $(seq 1 $((len + 2))))╗${NC}"
    echo -e "${PURPLE}║ $1 ║${NC}"
    echo -e "${PURPLE}╚$(printf '═%.0s' $(seq 1 $((len + 2))))╝${NC}"
    echo
}

print_step() {
    echo -e "${BLUE}🔄 [$1/$2] $3${NC}"
}

find_mcp_clients() {
    local clients=()
    
    # Check for VS Code
    if [[ -f "$HOME/.config/Code/User/settings.json" ]]; then
        clients+=("vscode:$HOME/.config/Code/User/settings.json:🔷 Visual Studio Code")
    fi
    
    # Check for Claude Desktop (macOS)
    if [[ "$OSTYPE" == "darwin"* ]] && [[ -d "$HOME/Library/Application Support/Claude" ]]; then
        local claude_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
        clients+=("claude:$claude_config:🤖 Claude Desktop")
    fi
    
    # Check for Claude Desktop (Linux)
    if [[ "$OSTYPE" == "linux-gnu"* ]] && [[ -d "$HOME/.config/Claude" ]]; then
        local claude_config="$HOME/.config/Claude/claude_desktop_config.json"
        clients+=("claude:$claude_config:🤖 Claude Desktop")
    fi
    
    # Check for Cursor
    if [[ -f "$HOME/.config/Cursor/User/settings.json" ]]; then
        clients+=("vscode:$HOME/.config/Cursor/User/settings.json:🔸 Cursor")
    fi
    
    printf '%s\n' "${clients[@]}"
}

configure_vscode_mcp() {
    local config_path="$1"
    local server_path="$2"
    
    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$config_path")"
    
    # Create or read existing settings
    if [[ -f "$config_path" ]]; then
        cp "$config_path" "$config_path.backup.$(date +%Y%m%d_%H%M%S)"
    else
        echo '{}' > "$config_path"
    fi
    
    # Use jq if available, otherwise use python
    if command -v jq >/dev/null 2>&1; then
        jq --arg server_path "$server_path" '
            .mcp.mcpServers."rust-analyzer-mcp-server" = {
                "command": $server_path,
                "args": []
            }
        ' "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
import sys

try:
    with open('$config_path', 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'mcp' not in config:
    config['mcp'] = {}

if 'mcpServers' not in config['mcp']:
    config['mcp']['mcpServers'] = {}

config['mcp']['mcpServers']['rust-analyzer-mcp-server'] = {
    'command': '$server_path',
    'args': []
}

with open('$config_path', 'w') as f:
    json.dump(config, f, indent=2)
"
    else
        print_warning "jq or python3 required for automatic VS Code configuration"
        return 1
    fi
    
    return 0
}

configure_claude_mcp() {
    local config_path="$1"
    local server_path="$2"
    
    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$config_path")"
    
    # Create or read existing config
    if [[ -f "$config_path" ]]; then
        cp "$config_path" "$config_path.backup.$(date +%Y%m%d_%H%M%S)"
    else
        echo '{}' > "$config_path"
    fi
    
    # Use jq if available, otherwise use python
    if command -v jq >/dev/null 2>&1; then
        jq --arg server_path "$server_path" '
            .mcpServers."rust-analyzer-mcp-server" = {
                "command": $server_path,
                "args": []
            }
        ' "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json

try:
    with open('$config_path', 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'mcpServers' not in config:
    config['mcpServers'] = {}

config['mcpServers']['rust-analyzer-mcp-server'] = {
    'command': '$server_path',
    'args': []
}

with open('$config_path', 'w') as f:
    json.dump(config, f, indent=2)
"
    else
        print_warning "jq or python3 required for automatic Claude configuration"
        return 1
    fi
    
    return 0
}

echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              🦀 Rust Analyzer MCP Server Installer          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_header() {
    echo -e "${PURPLE}=== $1 ===${NC}"
}

print_header "Rust Analyzer MCP Server Installer"
echo

# Check if running on supported OS
OS="$(uname -s)"
case "$OS" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          print_error "Unsupported operating system: $OS"
                exit 1;;
esac

print_info "Detected OS: $MACHINE"

# Check if Rust is installed
if command -v rustc &> /dev/null; then
    RUST_VERSION=$(rustc --version)
    print_success "Rust found: $RUST_VERSION"
else
    print_error "Rust is not installed or not in PATH"
    print_info "Please install Rust from https://rustup.rs/"
    exit 1
fi

# Check if rust-analyzer is available
if command -v rust-analyzer &> /dev/null; then
    RA_VERSION=$(rust-analyzer --version)
    print_success "rust-analyzer found: $RA_VERSION"
else
    print_warning "rust-analyzer not found in PATH"
    print_info "Installing rust-analyzer via rustup..."
    if rustup component add rust-analyzer; then
        print_success "rust-analyzer installed successfully"
    else
        print_error "Failed to install rust-analyzer"
        exit 1
    fi
fi

# Determine installation directory
if [ -n "$INSTALL_DIR" ]; then
    INSTALL_PATH="$INSTALL_DIR"
elif [ "$SYSTEM_WIDE" = true ]; then
    INSTALL_PATH="/usr/local/bin"
else
    INSTALL_PATH="$HOME/.local/bin"
fi

print_info "Installing to: $INSTALL_PATH"

# Create installation directory
if [ ! -d "$INSTALL_PATH" ]; then
    if [ "$SYSTEM_WIDE" = true ] && [ "$INSTALL_PATH" = "/usr/local/bin" ]; then
        if sudo mkdir -p "$INSTALL_PATH"; then
            print_success "Created installation directory (with sudo)"
        else
            print_error "Failed to create installation directory"
            exit 1
        fi
    else
        if mkdir -p "$INSTALL_PATH"; then
            print_success "Created installation directory"
        else
            print_error "Failed to create installation directory"
            exit 1
        fi
    fi
fi

# Build the project
print_info "Building Rust Analyzer MCP Server..."
if cargo build --release; then
    print_success "Build completed successfully"
else
    print_error "Failed to build project"
    exit 1
fi

# Copy binary to installation directory
BINARY_NAME="rust-analyzer-mcp-server"
SOURCE_PATH="./target/release/$BINARY_NAME"
DEST_PATH="$INSTALL_PATH/$BINARY_NAME"

if [ "$SYSTEM_WIDE" = true ] && [ "$INSTALL_PATH" = "/usr/local/bin" ]; then
    if sudo cp "$SOURCE_PATH" "$DEST_PATH"; then
        sudo chmod +x "$DEST_PATH"
        print_success "Binary copied to $DEST_PATH (with sudo)"
    else
        print_error "Failed to copy binary"
        exit 1
    fi
else
    if cp "$SOURCE_PATH" "$DEST_PATH"; then
        chmod +x "$DEST_PATH"
        print_success "Binary copied to $DEST_PATH"
    else
        print_error "Failed to copy binary"
        exit 1
    fi
fi

# Add to PATH if necessary
SHELL_RC=""
case "$SHELL" in
    */bash*)    SHELL_RC="$HOME/.bashrc";;
    */zsh*)     SHELL_RC="$HOME/.zshrc";;
    */fish*)    SHELL_RC="$HOME/.config/fish/config.fish";;
    *)          SHELL_RC="$HOME/.profile";;
esac

if [ "$SYSTEM_WIDE" = false ] && [ "$INSTALL_PATH" = "$HOME/.local/bin" ]; then
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        print_info "Adding $INSTALL_PATH to PATH in $SHELL_RC"
        
        # Add to shell RC file
        if [ -f "$SHELL_RC" ]; then
            if ! grep -q "$HOME/.local/bin" "$SHELL_RC"; then
                case "$SHELL" in
                    */fish*)
                        echo "set -gx PATH \$PATH $HOME/.local/bin" >> "$SHELL_RC"
                        ;;
                    *)
                        echo "export PATH=\"\$PATH:$HOME/.local/bin\"" >> "$SHELL_RC"
                        ;;
                esac
                print_success "Added to PATH in $SHELL_RC"
                print_warning "Please restart your terminal or run 'source $SHELL_RC' to use the command"
            else
                print_success "PATH already configured in $SHELL_RC"
            fi
        else
            print_warning "Shell RC file not found. Please manually add '$INSTALL_PATH' to your PATH"
        fi
    else
        print_success "Installation directory already in PATH"
    fi
fi

# Test installation
print_step 1 2 "Testing installation..."
export PATH="$INSTALL_PATH:$PATH"
if "$DEST_PATH" --version > /dev/null 2>&1; then
    VERSION_OUTPUT=$("$DEST_PATH" --version)
    print_success "Installation test passed: $VERSION_OUTPUT"
else
    print_error "Installation test failed"
    exit 1
fi

# Detect and configure MCP clients
if [ "$CONFIGURE_MCP" = true ]; then
    print_step 2 2 "Detecting MCP clients..."
    mapfile -t clients < <(find_mcp_clients)
    
    if [ ${#clients[@]} -gt 0 ]; then
        print_header "🔍 MCP Client Detection"
        print_info "Found ${#clients[@]} MCP client(s):"
        
        for client in "${clients[@]}"; do
            IFS=':' read -r type path display <<< "$client"
            echo -e "  $display"
        done
        
        echo
        echo -e "${YELLOW}💡 Would you like to automatically configure these clients?${NC}"
        echo -e "${NC}   This will add the Rust Analyzer MCP Server to their configuration files.${NC}"
        read -p "Configure MCP clients automatically? (Y/n): " response
        
        if [[ "$response" == "" || "$response" =~ ^[Yy] ]]; then
            echo
            print_header "⚙️  Configuring MCP Clients"
            
            for client in "${clients[@]}"; do
                IFS=':' read -r type config_path display <<< "$client"
                print_info "Configuring $(echo "$display" | sed 's/^[^ ]* //')..."
                
                success=false
                case "$type" in
                    "vscode")
                        if configure_vscode_mcp "$config_path" "$DEST_PATH"; then
                            success=true
                        fi
                        ;;
                    "claude")
                        if configure_claude_mcp "$config_path" "$DEST_PATH"; then
                            success=true
                        fi
                        ;;
                esac
                
                if [ "$success" = true ]; then
                    print_success "$(echo "$display" | cut -d' ' -f1) $(echo "$display" | sed 's/^[^ ]* //') configured successfully!"
                else
                    print_warning "$(echo "$display" | cut -d' ' -f1) Failed to configure $(echo "$display" | sed 's/^[^ ]* //')"
                fi
            done
            
            echo
            echo -e "${GREEN}🎉 MCP client configuration completed!${NC}"
            echo
            echo -e "${CYAN}📋 Next steps:${NC}"
            echo "  1. Restart your MCP clients (VS Code, Claude Desktop, etc.)"
            echo "  2. The Rust Analyzer MCP Server should now be available"
            echo "  3. Check the client logs if you encounter any issues"
            echo
        else
            print_info "Skipping automatic MCP client configuration"
            echo
            echo -e "${YELLOW}📖 Manual configuration:${NC}"
            echo "  • See the README.md file for manual setup instructions"
            echo "  • Server path: $DEST_PATH"
            echo
        fi
    else
        print_warning "No supported MCP clients detected"
        print_info "Supported clients: VS Code, Claude Desktop, Cursor"
        echo
        echo -e "${YELLOW}📖 Manual setup:${NC}"
        echo "  • Install a supported MCP client"
        echo "  • See the README.md file for configuration instructions"
        echo "  • Server path: $DEST_PATH"
        echo
    fi
fi

# Install uninstaller
print_info "Installing uninstaller..."
UNINSTALLER_NAME="rust-analyzer-mcp-server-uninstall.sh"
UNINSTALLER_PATH="$INSTALL_PATH/$UNINSTALLER_NAME"
if cp "uninstall.sh" "$UNINSTALLER_PATH" 2>/dev/null; then
    chmod +x "$UNINSTALLER_PATH"
    print_success "Uninstaller installed: $UNINSTALLER_PATH"
else
    print_warning "Could not install uninstaller"
fi

# Set up auto-start if requested
if [ "$AUTO_START" = true ]; then
    print_info "Setting up auto-start at system boot..."
    
    if [ "$SYSTEM_WIDE" = true ]; then
        # System-wide auto-start using systemd (Linux) or launchd (macOS)
        if command -v systemctl > /dev/null 2>&1; then
            # Linux with systemd
            SERVICE_FILE="/etc/systemd/system/rust-analyzer-mcp-server.service"
            cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rust Analyzer MCP Server
After=network.target

[Service]
Type=simple
ExecStart=$DEST_PATH /tmp
Restart=always
RestartSec=10
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable rust-analyzer-mcp-server.service
            print_success "Auto-start configured (systemd service): rust-analyzer-mcp-server.service"
        elif [ "$(uname)" = "Darwin" ]; then
            # macOS with launchd
            PLIST_FILE="/Library/LaunchDaemons/com.rust-analyzer-mcp-server.plist"
            cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rust-analyzer-mcp-server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST_PATH</string>
        <string>/tmp</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
            launchctl load "$PLIST_FILE"
            print_success "Auto-start configured (launchd): $PLIST_FILE"
        else
            print_warning "System-wide auto-start not supported on this system"
        fi
    else
        # User auto-start
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
ExecStart=$DEST_PATH %h
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable rust-analyzer-mcp-server.service
            print_success "Auto-start configured (systemd user service): rust-analyzer-mcp-server.service"
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
        <string>$DEST_PATH</string>
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
            print_success "Auto-start configured (launchd user): $PLIST_FILE"
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
                echo "$DEST_PATH \$HOME &" >> "$SHELL_RC"
                print_success "Auto-start configured (shell profile): $SHELL_RC"
            else
                print_warning "Could not set up auto-start: no suitable shell profile found"
            fi
        fi
    fi
fi

echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    🎉 Installation Complete! 🎉              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
print_success "🦀 Rust Analyzer MCP Server installed successfully!"
echo
echo -e "${CYAN}📍 Installation Details:${NC}"
echo "  • Location: $DEST_PATH"
echo "  • Uninstaller: $UNINSTALLER_PATH"
echo "  • Usage: rust-analyzer-mcp-server --help"
echo

if [ "$AUTO_START" = true ]; then
    echo -e "${GREEN}🚀 Auto-start: Enabled (will start at system boot)${NC}"
else
    echo -e "${YELLOW}💡 Tip: Use --auto-start to enable auto-start at boot${NC}"
fi

if [ "$SYSTEM_WIDE" = false ] && [ "$INSTALL_PATH" = "$HOME/.local/bin" ]; then
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo
        print_warning "🔄 Please restart your terminal or run 'source ~/.bashrc' to use the command"
    fi
fi

echo
echo -e "${PURPLE}📚 Resources:${NC}"
echo "  • Documentation: README.md"
echo "  • Issues: https://github.com/CireSnave/rust-analyzer-mcp-server/issues"
echo "  • Uninstall: Run the uninstaller or use quick-uninstall.sh"
echo
