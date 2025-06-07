#!/usr/bin/env bash
# Rust Analyzer MCP Server - Universal Quick Uninstaller
# This script works on Windows (Git Bash/WSL), Linux, and macOS

set -e

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

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux*)     OS_NAME="linux";;
    Darwin*)    OS_NAME="macos";;
    CYGWIN*|MINGW*|MSYS*) OS_NAME="windows";;
    *)          OS_NAME="unknown";;
esac

print_header "Rust Analyzer MCP Server - Universal Quick Uninstaller"
echo
print_info "Detected OS: $OS_NAME"

# Find the binary in common locations
BINARY_NAME="rust-analyzer-mcp-server"
UNINSTALLER_NAME="rust-analyzer-mcp-server-uninstall"
if [ "$OS_NAME" = "windows" ]; then
    BINARY_NAME="rust-analyzer-mcp-server.exe"
    UNINSTALLER_NAME="rust-analyzer-mcp-server-uninstall"
fi

FOUND_BINARIES=()
FOUND_UNINSTALLERS=()

# Common search paths
SEARCH_PATHS=(
    "$HOME/.local/bin"
    "$HOME/bin"
    "/usr/local/bin"
    "/usr/bin"
    "$HOME/.cargo/bin"
)

# Windows-specific paths
if [ "$OS_NAME" = "windows" ]; then
    SEARCH_PATHS+=(
        "$LOCALAPPDATA/RustAnalyzerMCP"
        "$PROGRAMFILES/RustAnalyzerMCP"
        "/c/Users/$USER/AppData/Local/RustAnalyzerMCP"
        "/c/Program Files/RustAnalyzerMCP"
    )
fi

print_info "Searching for installations..."

for search_path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$search_path/$BINARY_NAME" ]; then
        FOUND_BINARIES+=("$search_path/$BINARY_NAME")
        print_success "Found: $search_path/$BINARY_NAME"
    fi
    
    # Look for uninstallers
    for ext in ".sh" ".ps1" ".bat"; do
        uninstaller_path="$search_path/$UNINSTALLER_NAME$ext"
        if [ -f "$uninstaller_path" ]; then
            FOUND_UNINSTALLERS+=("$uninstaller_path")
            print_success "Found uninstaller: $uninstaller_path"
        fi
    done
done

# Also check PATH
if command -v "$BINARY_NAME" > /dev/null 2>&1; then
    WHICH_PATH=$(which "$BINARY_NAME" 2>/dev/null || command -v "$BINARY_NAME")
    if [[ ! " ${FOUND_BINARIES[@]} " =~ " ${WHICH_PATH} " ]]; then
        FOUND_BINARIES+=("$WHICH_PATH")
        print_success "Found in PATH: $WHICH_PATH"
    fi
fi

if [ ${#FOUND_BINARIES[@]} -eq 0 ] && [ ${#FOUND_UNINSTALLERS[@]} -eq 0 ]; then
    print_warning "No installations found."
    print_info "The MCP server may have already been uninstalled or was installed elsewhere."
    exit 0
fi

echo
total_items=$((${#FOUND_BINARIES[@]} + ${#FOUND_UNINSTALLERS[@]}))
print_warning "Found $total_items item(s). This will remove:"
for binary in "${FOUND_BINARIES[@]}"; do
    echo -e "${YELLOW}  • $binary${NC}"
done
for uninstaller in "${FOUND_UNINSTALLERS[@]}"; do
    echo -e "${YELLOW}  • $uninstaller (uninstaller)${NC}"
done
echo

read -p "Are you sure you want to continue? (y/N): " confirmation
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    print_info "Uninstallation cancelled."
    exit 0
fi

echo
print_info "Starting uninstallation..."

# Remove auto-start configuration
print_info "Removing auto-start configuration..."

if [ "$OS_NAME" = "windows" ]; then
    # Windows: Remove from Task Scheduler
    if command -v schtasks > /dev/null 2>&1; then
        schtasks /query /tn "RustAnalyzerMCPServer" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_info "Removing Windows scheduled task..."
            schtasks /delete /tn "RustAnalyzerMCPServer" /f >/dev/null 2>&1 || true
            print_success "Removed scheduled task"
        else
            print_info "No scheduled task found"
        fi
    fi
elif [ "$OS_NAME" = "macos" ]; then
    # macOS: Remove from LaunchAgents
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

# Stop any running processes
print_info "Stopping running processes..."
if command -v pkill > /dev/null 2>&1; then
    pkill -f "$BINARY_NAME" 2>/dev/null || true
elif command -v taskkill > /dev/null 2>&1; then
    taskkill /F /IM "$BINARY_NAME" 2>/dev/null || true
fi

# Remove each binary and uninstaller
ALL_FILES=("${FOUND_BINARIES[@]}" "${FOUND_UNINSTALLERS[@]}")

for file_path in "${ALL_FILES[@]}"; do
    print_info "Removing: $file_path"
    
    # Check if we need sudo
    if [[ "$file_path" == /usr/* ]] && [ "$OS_NAME" != "windows" ]; then
        if command -v sudo > /dev/null 2>&1; then
            sudo rm -f "$file_path"
        else
            print_error "sudo required but not available for: $file_path"
            continue
        fi
    else
        rm -f "$file_path"
    fi
    
    if [ ! -f "$file_path" ]; then
        print_success "Removed: $file_path"
    else
        print_error "Failed to remove: $file_path"
    fi
    
    # Remove parent directory if it's empty and looks like our installation
    PARENT_DIR=$(dirname "$file_path")
    if [[ "$PARENT_DIR" == *"RustAnalyzerMCP"* ]] && [ -d "$PARENT_DIR" ]; then
        if [ -z "$(ls -A "$PARENT_DIR" 2>/dev/null)" ]; then
            print_info "Removing empty directory: $PARENT_DIR"
            if [[ "$PARENT_DIR" == /usr/* ]] && [ "$OS_NAME" != "windows" ]; then
                sudo rmdir "$PARENT_DIR" 2>/dev/null || true
            else
                rmdir "$PARENT_DIR" 2>/dev/null || true
            fi
        fi
    fi
done

echo
print_success "Uninstallation completed!"
echo
print_info "Notes:"
echo "  • You may need to restart your terminal for PATH changes to take effect"
echo "  • Any MCP client configurations will need to be updated manually"
echo "  • Auto-start configuration has been removed from system services"
echo "  • Rust and rust-analyzer remain installed (not removed by this uninstaller)"
echo "  • Some PATH entries may need to be manually removed from shell configuration files"
echo
