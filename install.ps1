# Rust Analyzer MCP Server - Windows Installer
# Enhanced with automatic MCP client detection and configuration

param(
    [switch]$SystemWide = $false,
    [string]$InstallDir = "",
    [switch]$AutoStart = $false,
    [bool]$ConfigureMCP = $true,
    [switch]$Help = $false
)

if ($Help) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "             Rust Analyzer MCP Server Installer" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Green
    Write-Host "  .\install.ps1                       # Install to user directory"
    Write-Host "  .\install.ps1 -SystemWide           # Install system-wide (requires admin)"
    Write-Host "  .\install.ps1 -InstallDir C:\path   # Install to custom directory"
    Write-Host "  .\install.ps1 -AutoStart            # Install and enable auto-start at boot"
    Write-Host "  .\install.ps1 -ConfigureMCP:`$false  # Skip automatic MCP client configuration"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -SystemWide    Install system-wide (requires Administrator)"
    Write-Host "  -InstallDir    Specify custom installation directory"
    Write-Host "  -AutoStart     Enable auto-start at system boot"
    Write-Host "  -ConfigureMCP  Automatically configure detected MCP clients (default: true)"
    Write-Host "  -Help          Show this help message"
    Write-Host ""
    Write-Host "This installer will automatically detect and configure:" -ForegroundColor Magenta
    Write-Host "   • GitHub Copilot in VS Code"
    Write-Host "   • Claude Desktop"
    Write-Host "   • Other MCP-compatible clients"
    Write-Host ""
    exit 0
}

function Write-Success($message) {
    Write-Host "[SUCCESS] $message" -ForegroundColor Green
}

function Write-Error($message) {
    Write-Host "[ERROR] $message" -ForegroundColor Red
}

function Write-WarningMessage($message) {
    Write-Host "[WARNING] $message" -ForegroundColor Yellow
}

function Write-Info($message) {
    Write-Host "[INFO] $message" -ForegroundColor Cyan
}

function Write-Header($message) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host " $message" -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Step($step, $total, $message) {
    Write-Host "[$step/$total] $message" -ForegroundColor Blue
}

function Find-MCPClients {
    $clients = @()
    
    # Check for VS Code
    $vscodeConfigPath = "$env:APPDATA\Code\User\settings.json"
    if (Test-Path $vscodeConfigPath) {
        $client = New-Object PSObject -Property @{
            Name = "Visual Studio Code";
            Type = "VSCode";
            ConfigPath = $vscodeConfigPath;
            Icon = "[VS Code]"
        }
        $clients += $client
    }
    
    # Check for Claude Desktop
    $claudeConfigPath = "$env:APPDATA\Claude\claude_desktop_config.json"
    if (Test-Path $claudeConfigPath) {
        $client = New-Object PSObject -Property @{
            Name = "Claude Desktop";
            Type = "Claude";
            ConfigPath = $claudeConfigPath;
            Icon = "[Claude]"
        }
        $clients += $client
    }
    
    # Check for Cursor
    $cursorConfigPath = "$env:APPDATA\Cursor\User\settings.json"
    if (Test-Path $cursorConfigPath) {
        $client = New-Object PSObject -Property @{
            Name = "Cursor";
            Type = "VSCode";
            ConfigPath = $cursorConfigPath;
            Icon = "[Cursor]"
        }
        $clients += $client
    }
    
    return $clients
}

function Set-VSCodeMCP($configPath, $serverPath) {
    try {
        $settingsJson = Get-Content $configPath -Raw | ConvertFrom-Json
        
        if (-not $settingsJson.PSObject.Properties.Name.Contains("mcp")) {
            $settingsJson | Add-Member -Type NoteProperty -Name "mcp" -Value ([PSCustomObject]@{})
        }
        
        if (-not $settingsJson.mcp.PSObject.Properties.Name.Contains("mcpServers")) {
            $settingsJson.mcp | Add-Member -Type NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
        }
        
        $serverObject = [PSCustomObject]@{
            command = $serverPath
            args = @()
        }
        $settingsJson.mcp.mcpServers | Add-Member -Type NoteProperty -Name "rust-analyzer-mcp-server" -Value $serverObject -Force
        
        $settingsJson | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
        return $true
    }
    catch {
        Write-WarningMessage "Failed to configure VS Code: $($_.Exception.Message)"
        return $false
    }
}

function Set-ClaudeMCP($configPath, $serverPath) {
    try {
        if (Test-Path $configPath) {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
        } else {
            $config = [PSCustomObject]@{}
        }
        
        if (-not $config.PSObject.Properties.Name.Contains("mcpServers")) {
            $config | Add-Member -Type NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
        }
        $serverObject = [PSCustomObject]@{
            command = $serverPath
            args = @()
        }
        $config.mcpServers | Add-Member -Type NoteProperty -Name "rust-analyzer-mcp-server" -Value $serverObject -Force
        
        # Ensure directory exists
        $configDir = Split-Path $configPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        
        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
        return $true
    }
    catch {
        Write-WarningMessage "Failed to configure Claude Desktop: $($_.Exception.Message)"
        return $false
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "             Rust Analyzer MCP Server Installer" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if Rust is installed
try {
    $rustVersion = rustc --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Rust found: $rustVersion"
    } else {
        throw "Rust not found"
    }
} catch {
    Write-Error "Rust is not installed or not in PATH"
    Write-Info "Please install Rust from https://rustup.rs/"
    exit 1
}

# Check if rust-analyzer is available
try {
    $raVersion = rust-analyzer --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "rust-analyzer found: $raVersion"
    } else {
        Write-Warning "rust-analyzer not found in PATH"
        Write-Info "Installing rust-analyzer via rustup..."
        rustup component add rust-analyzer
        if ($LASTEXITCODE -eq 0) {
            Write-Success "rust-analyzer installed successfully"
        } else {
            Write-Error "Failed to install rust-analyzer"
            exit 1
        }
    }
} catch {
    Write-Error "Failed to check rust-analyzer"
    exit 1
}

# Determine installation directory
if ($InstallDir -ne "") {
    $installPath = $InstallDir
} elseif ($SystemWide) {
    $installPath = "$env:ProgramFiles\RustAnalyzerMCP"
} else {
    $installPath = "$env:LOCALAPPDATA\RustAnalyzerMCP"
}

Write-Info "Installing to: $installPath"

# Create installation directory
try {
    if (!(Test-Path $installPath)) {
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        Write-Success "Created installation directory"
    }
} catch {
    Write-Error "Failed to create installation directory: $_"
    exit 1
}

# Build the project
Write-Info "Building Rust Analyzer MCP Server..."
try {
    cargo build --release
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Build completed successfully"
    } else {
        throw "Build failed"
    }
} catch {
    Write-Error "Failed to build project: $_"
    exit 1
}

# Copy binary to installation directory
$binaryName = "rust-analyzer-mcp-server.exe"
$sourcePath = ".\target\release\$binaryName"
$destPath = "$installPath\$binaryName"

try {
    Copy-Item $sourcePath $destPath -Force
    Write-Success "Binary copied to $destPath"
} catch {
    Write-Error "Failed to copy binary: $_"
    exit 1
}

# Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($SystemWide) {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $target = "Machine"
} else {
    $target = "User"
}

if ($currentPath -notlike "*$installPath*") {
    try {
        $newPath = "$currentPath;$installPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, $target)
        Write-Success "Added to PATH ($target level)"
        Write-Warning "Please restart your terminal or PowerShell session to use the command"
    } catch {
        Write-Error "Failed to add to PATH: $_"
        Write-Info "You can manually add '$installPath' to your PATH environment variable"
    }
} else {
    Write-Success "Installation directory already in PATH"
}

# Test installation
Write-Step 1 2 "Testing installation..."
$env:PATH = "$installPath;$env:PATH"
try {
    $output = & "$destPath" --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Installation test passed: $output"
    } else {
        throw "Test failed"
    }
} catch {
    Write-Error "Installation test failed: $_"
    exit 1
}

# Detect and configure MCP clients
if ($ConfigureMCP) {
    Write-Step 2 2 "Detecting MCP clients..."
    $clients = Find-MCPClients
    
    if ($clients.Count -gt 0) {
        Write-Header "MCP Client Detection"
        Write-Info "Found $($clients.Count) MCP client(s):"
        
        foreach ($client in $clients) {
            Write-Host "  $($client.Icon) $($client.Name)" -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "Would you like to automatically configure these clients?" -ForegroundColor Yellow
        Write-Host "This will add the Rust Analyzer MCP Server to their configuration files." -ForegroundColor Gray
        $response = Read-Host "Configure MCP clients automatically? (Y/n)"
        
        if ($response -eq "" -or $response.ToLower() -eq "y" -or $response.ToLower() -eq "yes") {
            Write-Host ""
            Write-Header "Configuring MCP Clients"
            
            foreach ($client in $clients) {
                Write-Info "Configuring $($client.Name)..."
                
                $success = $false
                switch ($client.Type) {
                    "VSCode" {
                        $success = Set-VSCodeMCP $client.ConfigPath $destPath
                    }
                    "Claude" {
                        $success = Set-ClaudeMCP $client.ConfigPath $destPath
                    }
                }
                
                if ($success) {
                    Write-Success "$($client.Icon) $($client.Name) configured successfully!"
                } else {
                    Write-Warning "$($client.Icon) Failed to configure $($client.Name)"
                }
            }
            
            Write-Host ""
            Write-Host "MCP client configuration completed!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Next steps:" -ForegroundColor Cyan
            Write-Host "  1. Restart your MCP clients (VS Code, Claude Desktop, etc.)"
            Write-Host "  2. The Rust Analyzer MCP Server should now be available"
            Write-Host "  3. Check the client logs if you encounter any issues"
            Write-Host ""
        } else {
            Write-Info "Skipping automatic MCP client configuration"
            Write-Host ""
            Write-Host "Manual configuration:" -ForegroundColor Yellow
            Write-Host "  • See the README.md file for manual setup instructions"
            Write-Host "  • Server path: $destPath"
            Write-Host ""
        }
    } else {
        Write-Warning "No supported MCP clients detected"
        Write-Info "Supported clients: VS Code, Claude Desktop, Cursor"
        Write-Host ""
        Write-Host "Manual setup:" -ForegroundColor Yellow
        Write-Host "  • Install a supported MCP client"
        Write-Host "  • See the README.md file for configuration instructions"
        Write-Host "  • Server path: $destPath"
        Write-Host ""
    }
}

# Install uninstaller
Write-Info "Installing uninstaller..."
$uninstallerName = "rust-analyzer-mcp-server-uninstall.ps1"
$uninstallerPath = Join-Path $installPath $uninstallerName
try {
    Copy-Item "uninstall.ps1" $uninstallerPath -Force
    Write-Success "Uninstaller installed: $uninstallerPath"
} catch {
    Write-Warning "Could not install uninstaller: $_"
}

# Set up auto-start if requested
if ($AutoStart) {
    Write-Info "Setting up auto-start at system boot..."
    try {
        if ($SystemWide -or (Test-Path "$env:ProgramData")) {
            # System-wide auto-start using Task Scheduler
            $taskName = "RustAnalyzerMCPServer"
            $action = New-ScheduledTaskAction -Execute "$destPath" -Argument "."
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            Write-Success "Auto-start configured (Task Scheduler): $taskName"
        } else {
            # User auto-start using startup folder
            $startupFolder = [Environment]::GetFolderPath('Startup')
            $shortcutPath = Join-Path $startupFolder "Rust Analyzer MCP Server.lnk"
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $destPath
            $shortcut.Arguments = "."
            $shortcut.WorkingDirectory = [Environment]::GetFolderPath('MyDocuments')
            $shortcut.Description = "Rust Analyzer MCP Server"
            $shortcut.Save()
            Write-Success "Auto-start configured (Startup folder): $shortcutPath"
        }
    } catch {
        Write-Warning "Could not set up auto-start: $_"
        Write-Info "You can manually set up auto-start using Task Scheduler or the Startup folder"
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                    Installation Complete!" -ForegroundColor Green  
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Rust Analyzer MCP Server installed successfully!"
Write-Host ""
Write-Host "Installation Details:" -ForegroundColor Cyan
Write-Host "  • Location: $destPath" -ForegroundColor White
Write-Host "  • Uninstaller: $uninstallerPath" -ForegroundColor White
Write-Host "  • Usage: rust-analyzer-mcp-server --help" -ForegroundColor White
Write-Host ""

if ($AutoStart) {
    Write-Host "Auto-start: Enabled (will start at system boot)" -ForegroundColor Green
} else {
    Write-Host "Tip: Use -AutoStart to enable auto-start at boot" -ForegroundColor Yellow
}

if ($currentPath -notlike "*$installPath*") {
    Write-Host ""
    Write-Warning "Please restart your terminal to use the 'rust-analyzer-mcp-server' command"
}

Write-Host ""
Write-Host "Resources:" -ForegroundColor Magenta
Write-Host "  • Documentation: README.md"
Write-Host "  • Issues: https://github.com/CireSnave/rust-analyzer-mcp-server/issues"
Write-Host "  • Uninstall: Run the uninstaller or use quick-uninstall.sh"
Write-Host ""
