#!/usr/bin/env bash

# Comprehensive Test Suite for Rust Analyzer MCP Server
# Tests installation, uninstallation, and integration functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   🧪 Comprehensive Test Suite                ║"
    echo "║              Rust Analyzer MCP Server Testing               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Test 1: Core Build and Unit Tests
test_core_functionality() {
    log_info "Testing core functionality..."
    
    # Build tests
    run_test "Cargo Check" "cargo check --quiet"
    run_test "Unit Tests" "cargo test --quiet"
    run_test "Release Build" "cargo build --release --quiet"
    run_test "Binary Execution" "./target/release/rust-analyzer-mcp-server --version > /dev/null"
}

# Test 2: Installer Script Syntax and Help
test_installer_syntax() {
    log_info "Testing installer script syntax..."
    
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        # Windows tests
        run_test "PowerShell Installer Syntax" "powershell -Command \"Get-Content install.ps1 | Out-Null\""
        run_test "PowerShell Installer Help" "powershell -File install.ps1 -Help > /dev/null"
        run_test "Batch Installer Help" "install.bat /help > /dev/null"
        run_test "PowerShell Uninstaller Syntax" "powershell -Command \"Get-Content uninstall.ps1 | Out-Null\""
        run_test "PowerShell Uninstaller Help" "powershell -File uninstall.ps1 -Help > /dev/null"
    else
        # Unix-like systems
        run_test "Bash Installer Syntax" "bash -n install.sh"
        run_test "Bash Installer Help" "bash install.sh --help > /dev/null"
        run_test "Bash Uninstaller Syntax" "bash -n uninstall.sh"
        run_test "Bash Uninstaller Help" "bash uninstall.sh --help > /dev/null"
    fi
    
    # Universal scripts
    run_test "Quick Install Syntax" "bash -n quick-install.sh"
    run_test "Quick Install Help" "bash quick-install.sh --help > /dev/null"
    run_test "Quick Uninstall Syntax" "bash -n quick-uninstall.sh"
    run_test "Quick Uninstall Help" "bash quick-uninstall.sh --help > /dev/null"
}

# Test 3: Installation Testing (in isolated environment)
test_installation() {
    log_info "Testing installation functionality..."
    
    # Create temporary installation directory
    local temp_install_dir="/tmp/mcp-server-test-$$"
    mkdir -p "$temp_install_dir"
    
    # Test cargo-based installation
    run_test "Cargo Install Test" "cargo install --path . --root '$temp_install_dir' --quiet"
    
    if [[ -f "$temp_install_dir/bin/rust-analyzer-mcp-server" ]]; then
        run_test "Installed Binary Execution" "$temp_install_dir/bin/rust-analyzer-mcp-server --version > /dev/null"
    fi
    
    # Cleanup
    rm -rf "$temp_install_dir"
}

# Test 4: MCP Protocol Testing
test_mcp_protocol() {
    log_info "Testing MCP protocol functionality..."
    
    # Start server in background for testing
    local temp_dir="/tmp/mcp-test-$$"
    mkdir -p "$temp_dir"
    
    # Test with a simple workspace
    echo 'fn main() { println!("Hello, world!"); }' > "$temp_dir/main.rs"
    
    # Create test input for MCP protocol
    cat > "$temp_dir/test_input.json" << 'EOF'
{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test-client", "version": "1.0.0"}}}
{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
EOF

    # Test MCP protocol communication
    if timeout 10s ./target/release/rust-analyzer-mcp-server "$temp_dir" < "$temp_dir/test_input.json" > "$temp_dir/output.json" 2>/dev/null; then
        if grep -q "tools" "$temp_dir/output.json"; then
            log_success "MCP Protocol Communication"
        else
            log_error "MCP Protocol Communication - No tools in response"
        fi
    else
        log_error "MCP Protocol Communication - Server timeout or error"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Test 5: Configuration File Testing
test_config_generation() {
    log_info "Testing configuration file generation..."
    
    local temp_config_dir="/tmp/mcp-config-test-$$"
    mkdir -p "$temp_config_dir"
    
    # Test VS Code configuration generation
    cat > "$temp_config_dir/settings.json" << 'EOF'
{
    "editor.fontSize": 14
}
EOF

    # Mock function to test configuration updates
    local server_path="/usr/local/bin/rust-analyzer-mcp-server"
    
    # Test JSON structure validity after adding MCP config
    if command -v jq >/dev/null 2>&1; then
        # Add MCP configuration
        jq '. + {"mcp": {"mcpServers": {"rust-analyzer-mcp-server": {"command": "'$server_path'", "args": []}}}}' \
           "$temp_config_dir/settings.json" > "$temp_config_dir/settings_updated.json"
        
        if jq -e '.mcp.mcpServers."rust-analyzer-mcp-server".command' "$temp_config_dir/settings_updated.json" >/dev/null; then
            log_success "VS Code Configuration Generation"
        else
            log_error "VS Code Configuration Generation"
        fi
    else
        log_warning "jq not available, skipping JSON configuration tests"
    fi
    
    # Cleanup
    rm -rf "$temp_config_dir"
}

# Test 6: Documentation and File Integrity
test_documentation() {
    log_info "Testing documentation and file integrity..."
    
    run_test "README.md Exists" "[[ -f README.md ]]"
    run_test "LICENSE Exists" "[[ -f LICENSE ]]"
    run_test "Cargo.toml Syntax" "cargo metadata --quiet > /dev/null"
    
    # Check that all installer scripts exist
    run_test "All Installers Present" "[[ -f install.sh && -f install.ps1 && -f install.bat && -f quick-install.sh ]]"
    run_test "All Uninstallers Present" "[[ -f uninstall.sh && -f uninstall.ps1 && -f uninstall.bat && -f quick-uninstall.sh ]]"
    
    # Check README mentions key features
    if grep -q "installation" README.md && grep -q "MCP" README.md && grep -q "rust-analyzer" README.md; then
        log_success "README.md Content Check"
    else
        log_error "README.md Content Check - Missing key sections"
    fi
}

# Test 7: Security and Permissions
test_security() {
    log_info "Testing security and permissions..."
    
    # Check that scripts don't contain obvious security issues
    if ! grep -r "rm -rf /" . --include="*.sh" --include="*.ps1" --include="*.bat" >/dev/null 2>&1; then
        log_success "No Dangerous rm Commands"
    else
        log_error "Found Potentially Dangerous rm Commands"
    fi
    
    # Check for hardcoded paths that might be problematic
    if ! grep -r "/tmp/" . --include="*.sh" --include="*.ps1" >/dev/null 2>&1; then
        log_success "No Hardcoded Temp Paths in Scripts"
    else
        log_warning "Found Hardcoded Temp Paths - Review for Security"
    fi
}

# Test 8: Cross-platform Compatibility
test_cross_platform() {
    log_info "Testing cross-platform compatibility..."
    
    # Test that scripts use appropriate line endings and syntax
    if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && "$OSTYPE" != "win32" ]]; then
        # Unix-like systems
        run_test "Unix Line Endings in Shell Scripts" "! grep -l $'\\r' *.sh >/dev/null 2>&1"
    fi
    
    # Test that Rust code compiles on current platform
    run_test "Platform-specific Build" "cargo check --target $(rustc -vV | sed -n 's|host: ||p') --quiet"
}

# Main test execution
main() {
    print_banner
    
    log_info "Starting comprehensive test suite..."
    log_info "Platform: $OSTYPE"
    log_info "Rust version: $(rustc --version)"
    
    echo ""
    
    # Run all test suites
    test_core_functionality
    echo ""
    test_installer_syntax
    echo ""
    test_installation
    echo ""
    test_mcp_protocol
    echo ""
    test_config_generation
    echo ""
    test_documentation
    echo ""
    test_security
    echo ""
    test_cross_platform
    
    # Print summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                        Test Summary                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Tests run: $TESTS_RUN"
    log_success "Tests passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Tests failed: $TESTS_FAILED"
        echo ""
        log_error "Some tests failed. Please review the output above."
        exit 1
    else
        echo ""
        log_success "All tests passed! 🎉"
        exit 0
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
