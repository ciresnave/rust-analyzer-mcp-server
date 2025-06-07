#!/bin/bash
# Rust Analyzer MCP Server - Unix Uninstaller (Linux/macOS)
# Usage: ./uninstall.sh [--system-wide] [--install-dir /path] [--force] [--help]

set -e

# Default values
SYSTEM_WIDE=false
INSTALL_DIR=""
FORCE=false
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
        --force)
            FORCE=true
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
Rust Analyzer MCP Server - Unix Uninstaller

Usage:
  ./uninstall.sh                          # Remove user installation
  ./uninstall.sh --system-wide             # Remove system-wide installation (requires sudo)
  ./uninstall.sh --install-dir /custom/path # Remove from custom directory
  ./uninstall.sh --force                  # Skip confirmation prompts

Options:
  --system-wide    Remove system-wide installation (requires sudo)
  --install-dir    Specify custom installation directory
  --force          Skip confirmation prompts
  --help          Show this help message

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

print_header "Rust Analyzer MCP Server Uninstaller"
echo

# Determine installation directory and binary name
BINARY_NAME="rust-analyzer-mcp-server"

if [ -n "$INSTALL_DIR" ]; then
    TARGET_DIR="$INSTALL_DIR"
    print_info "Using custom directory: $TARGET_DIR"
elif [ "$SYSTEM_WIDE" = true ]; then
    TARGET_DIR="/usr/local/bin"
    print_info "Removing system-wide installation"
else
    TARGET_DIR="$HOME/.local/bin"
    print_info "Removing user installation"
fi

BINARY_PATH="$TARGET_DIR/$BINARY_NAME"

# Check if installation exists
if [ ! -f "$BINARY_PATH" ]; then
    print_warning "MCP server not found at: $BINARY_PATH"
    print_info "Checking other common locations..."
    
    # Check other common locations
    USER_PATH="$HOME/.local/bin/$BINARY_NAME"
    SYSTEM_PATH="/usr/local/bin/$BINARY_NAME"
    USR_BIN_PATH="/usr/bin/$BINARY_NAME"
    
    if [ -f "$USER_PATH" ]; then
        print_info "Found user installation at: $USER_PATH"
        TARGET_DIR="$HOME/.local/bin"
        BINARY_PATH="$USER_PATH"
    elif [ -f "$SYSTEM_PATH" ]; then
        print_info "Found system installation at: $SYSTEM_PATH"
        TARGET_DIR="/usr/local/bin"
        BINARY_PATH="$SYSTEM_PATH"
    elif [ -f "$USR_BIN_PATH" ]; then
        print_info "Found system installation at: $USR_BIN_PATH"
        TARGET_DIR="/usr/bin"
        BINARY_PATH="$USR_BIN_PATH"
    else
        print_error "No installation found. Nothing to uninstall."
        exit 1
    fi
fi

print_info "Found installation at: $BINARY_PATH"

# Check if we need sudo for removal
NEED_SUDO=false
if [ "$TARGET_DIR" = "/usr/local/bin" ] || [ "$TARGET_DIR" = "/usr/bin" ] || [[ "$TARGET_DIR" == /usr/* ]]; then
    NEED_SUDO=true
fi

# Confirmation prompt
if [ "$FORCE" != true ]; then
    echo
    print_warning "This will remove the Rust Analyzer MCP Server:"
    echo -e "${YELLOW}  Binary: $BINARY_PATH${NC}"
    if [ "$NEED_SUDO" = true ]; then
        echo -e "${YELLOW}  Note: This requires sudo privileges${NC}"
    fi
    echo
    
    read -p "Are you sure you want to continue? (y/N): " confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled."
        exit 0
    fi
fi

echo
print_info "Starting uninstallation..."

# Stop any running instances
print_info "Checking for running processes..."
if pgrep -f "$BINARY_NAME" > /dev/null 2>&1; then
    print_info "Stopping running MCP server processes..."
    pkill -f "$BINARY_NAME" || true
    sleep 1
    # Force kill if still running
    if pgrep -f "$BINARY_NAME" > /dev/null 2>&1; then
        pkill -9 -f "$BINARY_NAME" || true
    fi
    print_success "Stopped running processes"
fi

# Remove auto-start configuration
print_info "Removing auto-start configuration..."

# macOS: Remove from LaunchAgents
if [[ "$OSTYPE" == "darwin"* ]]; then
    LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.rust-analyzer-mcp-server.plist"
    if [ -f "$LAUNCHD_PLIST" ]; then
        print_info "Removing macOS LaunchAgent..."
        launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
        rm -f "$LAUNCHD_PLIST"
        print_success "Removed LaunchAgent configuration"
    else
        print_info "No LaunchAgent configuration found"
    fi
else
    # Linux: Remove from systemd user service
    SYSTEMD_SERVICE="$HOME/.config/systemd/user/rust-analyzer-mcp-server.service"
    if [ -f "$SYSTEMD_SERVICE" ]; then
        print_info "Removing systemd user service..."
        systemctl --user stop rust-analyzer-mcp-server 2>/dev/null || true
        systemctl --user disable rust-analyzer-mcp-server 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE"
        systemctl --user daemon-reload 2>/dev/null || true
        print_success "Removed systemd service configuration"
    else
        print_info "No systemd service configuration found"
    fi
    
    # Also check for desktop autostart entry
    AUTOSTART_DESKTOP="$HOME/.config/autostart/rust-analyzer-mcp-server.desktop"
    if [ -f "$AUTOSTART_DESKTOP" ]; then
        print_info "Removing desktop autostart entry..."
        rm -f "$AUTOSTART_DESKTOP"
        print_success "Removed desktop autostart entry"
    fi
fi

# Remove the binary and uninstaller
print_info "Removing binary..."
if [ "$NEED_SUDO" = true ]; then
    if command -v sudo > /dev/null 2>&1; then
        sudo rm -f "$BINARY_PATH"
        # Also try to remove uninstaller with matching name
        UNINSTALLER_PATH="${BINARY_PATH%/*}/rust-analyzer-mcp-server-uninstall.sh"
        if [ -f "$UNINSTALLER_PATH" ]; then
            sudo rm -f "$UNINSTALLER_PATH"
            print_success "Removed uninstaller: $UNINSTALLER_PATH"
        fi
    else
        print_error "sudo not available but required for system-wide uninstall"
        exit 1
    fi
else
    rm -f "$BINARY_PATH"
    # Also try to remove uninstaller with matching name
    UNINSTALLER_PATH="${BINARY_PATH%/*}/rust-analyzer-mcp-server-uninstall.sh"
    if [ -f "$UNINSTALLER_PATH" ]; then
        rm -f "$UNINSTALLER_PATH"
        print_success "Removed uninstaller: $UNINSTALLER_PATH"
    fi
fi

if [ ! -f "$BINARY_PATH" ]; then
    print_success "Removed binary: $BINARY_PATH"
else
    print_error "Failed to remove binary: $BINARY_PATH"
    exit 1
fi

# Update PATH in shell configuration files (best effort)
print_info "Checking shell configuration files for PATH entries..."

# Common shell config files
CONFIG_FILES=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.zshrc"
    "$HOME/.profile"
)

for config_file in "${CONFIG_FILES[@]}"; do
    if [ -f "$config_file" ] && grep -q "$TARGET_DIR" "$config_file" 2>/dev/null; then
        # Create a backup
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove lines that add TARGET_DIR to PATH
        if command -v sed > /dev/null 2>&1; then
            # Use different sed syntax for macOS vs Linux
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "/export PATH.*$TARGET_DIR/d" "$config_file" 2>/dev/null || true
                sed -i '' "/PATH.*$TARGET_DIR/d" "$config_file" 2>/dev/null || true
            else
                sed -i "/export PATH.*$(echo "$TARGET_DIR" | sed 's/[\/&]/\\&/g')/d" "$config_file" 2>/dev/null || true
                sed -i "/PATH.*$(echo "$TARGET_DIR" | sed 's/[\/&]/\\&/g')/d" "$config_file" 2>/dev/null || true
            fi
            print_info "Updated $config_file (backup created)"
        fi
    fi
done

echo
print_success "Rust Analyzer MCP Server has been successfully uninstalled!"
echo
print_info "Notes:"
echo "  • You may need to restart your terminal for PATH changes to take effect"
echo "  • Any MCP client configurations will need to be updated manually"
echo "  • Auto-start configuration has been removed from system services"
echo "  • Rust and rust-analyzer remain installed (not removed by this uninstaller)"
echo "  • Shell configuration backups were created with .backup timestamp"
echo
