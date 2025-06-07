# Rust Analyzer MCP Server - Windows Uninstaller
# Run this script in PowerShell to remove the MCP server

param(
    [switch]$SystemWide = $false,
    [string]$InstallDir = "",
    [switch]$Help = $false,
    [switch]$Force = $false
)

if ($Help) {
    Write-Host "Rust Analyzer MCP Server - Windows Uninstaller"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\uninstall.ps1                     # Remove user installation"
    Write-Host "  .\uninstall.ps1 -SystemWide         # Remove system-wide installation (requires admin)"
    Write-Host "  .\uninstall.ps1 -InstallDir C:\path # Remove from custom directory"
    Write-Host "  .\uninstall.ps1 -Force              # Skip confirmation prompts"
    Write-Host ""
    exit 0
}

# Colors for output
function Write-Success($message) {
    Write-Host "✓ $message" -ForegroundColor Green
}

function Write-Error($message) {
    Write-Host "✗ $message" -ForegroundColor Red
}

function Write-Warning($message) {
    Write-Host "⚠ $message" -ForegroundColor Yellow
}

function Write-Info($message) {
    Write-Host "ℹ $message" -ForegroundColor Cyan
}

Write-Host "=== Rust Analyzer MCP Server Uninstaller ===" -ForegroundColor Magenta
Write-Host ""

# Determine installation directory
if ($InstallDir -ne "") {
    $TargetDir = $InstallDir
    Write-Info "Using custom directory: $TargetDir"
} elseif ($SystemWide) {
    $TargetDir = "$env:ProgramFiles\RustAnalyzerMCP"
    Write-Info "Removing system-wide installation"
} else {
    $TargetDir = "$env:LOCALAPPDATA\RustAnalyzerMCP"
    Write-Info "Removing user installation"
}

$BinaryPath = Join-Path $TargetDir "rust-analyzer-mcp-server.exe"

# Check if installation exists
if (-not (Test-Path $BinaryPath)) {
    Write-Warning "MCP server not found at: $BinaryPath"
    Write-Info "Installation may have already been removed or was installed elsewhere."
    
    # Check other common locations
    $UserPath = "$env:LOCALAPPDATA\RustAnalyzerMCP\rust-analyzer-mcp-server.exe"
    $SystemPath = "$env:ProgramFiles\RustAnalyzerMCP\rust-analyzer-mcp-server.exe"
    
    if (Test-Path $UserPath) {
        Write-Info "Found user installation at: $UserPath"
        $TargetDir = "$env:LOCALAPPDATA\RustAnalyzerMCP"
        $BinaryPath = $UserPath
    } elseif (Test-Path $SystemPath) {
        Write-Info "Found system installation at: $SystemPath"
        $TargetDir = "$env:ProgramFiles\RustAnalyzerMCP"
        $BinaryPath = $SystemPath
    } else {
        Write-Error "No installation found. Nothing to uninstall."
        exit 1
    }
}

Write-Info "Found installation at: $BinaryPath"

# Confirmation prompt
if (-not $Force) {
    Write-Host ""
    Write-Warning "This will remove the Rust Analyzer MCP Server and its installation directory:"
    Write-Host "  Directory: $TargetDir" -ForegroundColor Yellow
    Write-Host "  Binary: $BinaryPath" -ForegroundColor Yellow
    Write-Host ""
    
    $confirmation = Read-Host "Are you sure you want to continue? (y/N)"
    if ($confirmation -notmatch '^[Yy]$') {
        Write-Info "Uninstallation cancelled."
        exit 0
    }
}

Write-Host ""
Write-Info "Starting uninstallation..."

# Stop any running instances
try {
    $processes = Get-Process -Name "rust-analyzer-mcp-server" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Info "Stopping running MCP server processes..."
        $processes | Stop-Process -Force
        Write-Success "Stopped running processes"
    }
} catch {
    Write-Warning "Could not check for running processes: $($_.Exception.Message)"
}

# Remove auto-start configurations
Write-Info "Removing auto-start configurations..."
try {
    # Remove Task Scheduler task
    $task = Get-ScheduledTask -TaskName "RustAnalyzerMCPServer" -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName "RustAnalyzerMCPServer" -Confirm:$false
        Write-Success "Removed auto-start task from Task Scheduler"
    }
    
    # Remove startup folder shortcut
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "Rust Analyzer MCP Server.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force
        Write-Success "Removed startup shortcut"
    }
} catch {
    Write-Warning "Could not remove auto-start configurations: $($_.Exception.Message)"
}

# Remove the binary and directory
try {
    if (Test-Path $TargetDir) {
        Remove-Item -Path $TargetDir -Recurse -Force
        Write-Success "Removed installation directory: $TargetDir"
    }
} catch {
    Write-Error "Failed to remove installation directory: $($_.Exception.Message)"
    exit 1
}

# Remove from PATH
try {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -like "*$TargetDir*") {
        $newPath = ($currentPath -split ';' | Where-Object { $_ -ne $TargetDir }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Success "Removed from PATH (user)"
    }
    
    if ($SystemWide) {
        $currentSystemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($currentSystemPath -like "*$TargetDir*") {
            $newSystemPath = ($currentSystemPath -split ';' | Where-Object { $_ -ne $TargetDir }) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newSystemPath, "Machine")
            Write-Success "Removed from PATH (system)"
        }
    }
} catch {
    Write-Warning "Could not update PATH: $($_.Exception.Message)"
    Write-Info "You may need to manually remove '$TargetDir' from your PATH environment variable"
}

Write-Host ""
Write-Success "Rust Analyzer MCP Server has been successfully uninstalled!"
Write-Host ""
Write-Info "Notes:"
Write-Host "  • You may need to restart your terminal/command prompt for PATH changes to take effect"
Write-Host "  • Any MCP client configurations will need to be updated manually"
Write-Host "  • Rust and rust-analyzer remain installed (not removed by this uninstaller)"
Write-Host ""
