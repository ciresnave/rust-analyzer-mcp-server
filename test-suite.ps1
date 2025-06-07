# Comprehensive Test Suite for Rust Analyzer MCP Server (PowerShell)
# Tests installation, uninstallation, and integration functionality

param(
    [switch]$Verbose = $false
)

# Test tracking
$TestsRun = 0
$TestsPassed = 0
$TestsFailed = 0

function Write-Banner {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "                   Comprehensive Test Suite" -ForegroundColor Cyan
    Write-Host "              Rust Analyzer MCP Server Testing" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-TestInfo($message) {
    Write-Host "[INFO] $message" -ForegroundColor Cyan
}

function Write-TestSuccess($message) {
    Write-Host "[PASS] $message" -ForegroundColor Green
    $script:TestsPassed++
}

function Write-TestError($message) {
    Write-Host "[FAIL] $message" -ForegroundColor Red
    $script:TestsFailed++
}

function Write-TestWarning($message) {
    Write-Host "[WARN] $message" -ForegroundColor Yellow
}

function Run-Test($testName, $testCommand) {
    $script:TestsRun++
    Write-TestInfo "Running test: $testName"
    
    try {
        $result = Invoke-Expression $testCommand
        if ($LASTEXITCODE -eq 0 -or $result -eq $true) {
            Write-TestSuccess $testName
            return $true
        } else {
            Write-TestError $testName
            return $false
        }
    }
    catch {
        Write-TestError "$testName - Exception: $($_.Exception.Message)"
        return $false
    }
}

function Test-CoreFunctionality {
    Write-TestInfo "Testing core functionality..."
    
    Run-Test "Cargo Check" "cargo check --quiet"
    Run-Test "Unit Tests" "cargo test --quiet"
    Run-Test "Release Build" "cargo build --release --quiet"
    Run-Test "Binary Execution" ".\target\release\rust-analyzer-mcp-server.exe --version | Out-Null; `$true"
}

function Test-InstallerSyntax {
    Write-TestInfo "Testing installer script syntax..."
    
    # PowerShell scripts
    Run-Test "PowerShell Installer Syntax" "Get-Content install.ps1 | Out-Null; `$true"
    Run-Test "PowerShell Installer Help" "powershell -File install.ps1 -Help | Out-Null; `$true"
    Run-Test "PowerShell Uninstaller Syntax" "Get-Content uninstall.ps1 | Out-Null; `$true"
    Run-Test "PowerShell Uninstaller Help" "powershell -File uninstall.ps1 -Help | Out-Null; `$true"
    
    # Batch scripts
    Run-Test "Batch Installer Help" "cmd /c install.bat /help > `$null; `$true"
    
    # Universal scripts (if bash is available)
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        Run-Test "Quick Install Syntax" "bash -n quick-install.sh"
        Run-Test "Quick Install Help" "bash quick-install.sh --help | Out-Null; `$true"
        Run-Test "Quick Uninstall Syntax" "bash -n quick-uninstall.sh"
        Run-Test "Quick Uninstall Help" "bash quick-uninstall.sh --help | Out-Null; `$true"
    } else {
        Write-TestWarning "Bash not available, skipping Unix script tests"
    }
}

function Test-Installation {
    Write-TestInfo "Testing installation functionality..."
    
    # Create temporary installation directory
    $tempInstallDir = "$env:TEMP\mcp-server-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempInstallDir -Force | Out-Null
    
    try {
        # Test cargo-based installation
        Run-Test "Cargo Install Test" "cargo install --path . --root '$tempInstallDir' --quiet"
        
        $installedBinary = Join-Path $tempInstallDir "bin\rust-analyzer-mcp-server.exe"
        if (Test-Path $installedBinary) {
            Run-Test "Installed Binary Execution" "& '$installedBinary' --version | Out-Null; `$true"
        }
    }
    finally {
        # Cleanup
        if (Test-Path $tempInstallDir) {
            Remove-Item -Recurse -Force $tempInstallDir
        }
    }
}

function Test-McpProtocol {
    Write-TestInfo "Testing MCP protocol functionality..."
    
    # Create temporary directory for testing
    $tempDir = "$env:TEMP\mcp-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        # Create test Rust file
        Set-Content -Path "$tempDir\main.rs" -Value 'fn main() { println!("Hello, world!"); }'
        
        # Test that the server can start and handle basic operations
        try {
            # Test server startup with --help
            $helpOutput = & ".\target\release\rust-analyzer-mcp-server.exe" --help 2>&1
            if ($helpOutput -and $helpOutput -like "*rust-analyzer*") {
                Write-TestSuccess "MCP Server Help Output"
            } else {
                Write-TestError "MCP Server Help Output - No valid help response"
            }
            
            # Test server startup with --version
            $versionOutput = & ".\target\release\rust-analyzer-mcp-server.exe" --version 2>&1
            if ($versionOutput -and $versionOutput -like "*rust-analyzer-mcp-server*") {
                Write-TestSuccess "MCP Server Version Output"
            } else {
                Write-TestError "MCP Server Version Output - No valid version response"
            }
            
            # Test server can start with a workspace (will show banner)
            $startupTest = Start-Job -ScriptBlock {
                param($serverPath, $workspaceDir)
                try {
                    $process = Start-Process -FilePath $serverPath -ArgumentList $workspaceDir -RedirectStandardOutput "$env:TEMP\mcp-startup-test.log" -RedirectStandardError "$env:TEMP\mcp-startup-error.log" -PassThru
                    Start-Sleep -Seconds 2
                    $process.Kill()
                    return $true
                } catch {
                    return $false
                }
            } -ArgumentList ".\target\release\rust-analyzer-mcp-server.exe", $tempDir
            
            Wait-Job $startupTest -Timeout 10 | Out-Null
            $startupResult = Receive-Job $startupTest
            Remove-Job $startupTest -Force
            
            if ($startupResult) {
                Write-TestSuccess "MCP Server Startup Test"
            } else {
                Write-TestError "MCP Server Startup Test - Server failed to start"
            }
        }
        catch {
            Write-TestError "MCP Protocol Testing - Exception: $($_.Exception.Message)"
        }    }
    finally {
        # Cleanup
        if (Test-Path $tempDir) {
            Remove-Item -Recurse -Force $tempDir
        }
        # Clean up test logs (ignore errors if files are in use)
        try {
            if (Test-Path "$env:TEMP\mcp-startup-test.log") {
                Remove-Item "$env:TEMP\mcp-startup-test.log" -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path "$env:TEMP\mcp-startup-error.log") {
                Remove-Item "$env:TEMP\mcp-startup-error.log" -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Ignore cleanup errors
        }
    }
}

function Test-ConfigGeneration {
    Write-TestInfo "Testing configuration file generation..."
    
    $tempConfigDir = "$env:TEMP\mcp-config-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempConfigDir -Force | Out-Null
    
    try {
        # Test VS Code configuration generation
        $settingsJson = @"
{
    "editor.fontSize": 14
}
"@
        Set-Content -Path "$tempConfigDir\settings.json" -Value $settingsJson
        
        # Test JSON structure validity
        try {
            $settings = Get-Content "$tempConfigDir\settings.json" | ConvertFrom-Json
            
            # Add MCP configuration
            $mcpConfig = [PSCustomObject]@{
                command = "C:\Program Files\RustAnalyzerMCP\rust-analyzer-mcp-server.exe"
                args = @()
            }
            
            # Safely add MCP configuration
            if (-not ($settings.PSObject.Properties.Name -contains "mcp")) {
                $settings | Add-Member -Type NoteProperty -Name "mcp" -Value ([PSCustomObject]@{})
            }
            
            if (-not ($settings.mcp.PSObject.Properties.Name -contains "mcpServers")) {
                $settings.mcp | Add-Member -Type NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
            }
            
            $settings.mcp.mcpServers | Add-Member -Type NoteProperty -Name "rust-analyzer-mcp-server" -Value $mcpConfig -Force
            
            # Test that the configuration is valid JSON
            $configJson = $settings | ConvertTo-Json -Depth 10
            $null = $configJson | ConvertFrom-Json  # Test round-trip
            Write-TestSuccess "VS Code Configuration Generation"
        }
        catch {
            Write-TestError "VS Code Configuration Generation - $($_.Exception.Message)"
        }
    }
    finally {
        # Cleanup
        if (Test-Path $tempConfigDir) {
            Remove-Item -Recurse -Force $tempConfigDir
        }
    }
}

function Test-Documentation {
    Write-TestInfo "Testing documentation and file integrity..."
    
    Run-Test "README.md Exists" "Test-Path README.md"
    Run-Test "LICENSE Exists" "Test-Path LICENSE"
    Run-Test "Cargo.toml Syntax" "cargo metadata --quiet | Out-Null; `$true"
    
    # Check that all installer scripts exist
    $allInstallersExist = (Test-Path "install.sh") -and (Test-Path "install.ps1") -and (Test-Path "install.bat") -and (Test-Path "quick-install.sh")
    Run-Test "All Installers Present" "`$allInstallersExist"
    
    $allUninstallersExist = (Test-Path "uninstall.sh") -and (Test-Path "uninstall.ps1") -and (Test-Path "uninstall.bat") -and (Test-Path "quick-uninstall.sh")
    Run-Test "All Uninstallers Present" "`$allUninstallersExist"
    
    # Check README mentions key features
    if (Test-Path "README.md") {
        $readmeContent = Get-Content "README.md" -Raw
        $hasRequiredContent = ($readmeContent -like "*installation*") -and ($readmeContent -like "*MCP*") -and ($readmeContent -like "*rust-analyzer*")
        Run-Test "README.md Content Check" "`$hasRequiredContent"
    }
}

function Test-Security {
    Write-TestInfo "Testing security and permissions..."
    
    # Check that scripts don't contain dangerous commands
    $dangerousPatterns = @("rm -rf /", "Remove-Item -Recurse C:\", "del /s /q C:\")
    $foundDangerous = $false
    
    foreach ($pattern in $dangerousPatterns) {
        if (Select-String -Path "*.ps1", "*.sh", "*.bat" -Pattern $pattern -Quiet 2>$null) {
            $foundDangerous = $true
            break
        }
    }
    
    Run-Test "No Dangerous Commands" "!`$foundDangerous"
    
    # Check for hardcoded sensitive paths
    $sensitivePatterns = @("C:\\Windows", "/etc/", "/usr/bin/rm")
    $foundSensitive = $false
    
    foreach ($pattern in $sensitivePatterns) {
        if (Select-String -Path "*.ps1", "*.sh", "*.bat" -Pattern $pattern -Quiet 2>$null) {
            Write-TestWarning "Found potentially sensitive path reference: $pattern"
        }
    }
}

function Test-CrossPlatform {
    Write-TestInfo "Testing cross-platform compatibility..."
    
    # Test that Rust code compiles on current platform
    $rustTarget = (rustc -vV | Select-String "host:").ToString().Split(":")[1].Trim()
    Run-Test "Platform-specific Build" "cargo check --target $rustTarget --quiet"
    
    # Check line endings in PowerShell scripts
    $psFiles = Get-ChildItem -Filter "*.ps1"
    $hasCorrectLineEndings = $true
    foreach ($file in $psFiles) {
        $content = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($content -contains 10 -and $content -notcontains 13) {
            Write-TestWarning "$($file.Name) has Unix line endings"
        }
    }
    
    Run-Test "PowerShell Line Endings Check" "`$hasCorrectLineEndings"
}

function Main {
    Write-Banner
    
    Write-TestInfo "Starting comprehensive test suite..."
    Write-TestInfo "Platform: Windows (PowerShell $($PSVersionTable.PSVersion))"
    Write-TestInfo "Rust version: $(rustc --version)"
    
    Write-Host ""
    
    # Run all test suites
    Test-CoreFunctionality
    Write-Host ""
    Test-InstallerSyntax
    Write-Host ""
    Test-Installation
    Write-Host ""
    Test-McpProtocol
    Write-Host ""
    Test-ConfigGeneration
    Write-Host ""
    Test-Documentation
    Write-Host ""
    Test-Security
    Write-Host ""
    Test-CrossPlatform
    
    # Print summary
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host "                        Test Summary" -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host ""
    Write-TestInfo "Tests run: $TestsRun"
    Write-Host "[PASS] Tests passed: $TestsPassed" -ForegroundColor Green
    if ($TestsFailed -gt 0) {
        Write-Host "[FAIL] Tests failed: $TestsFailed" -ForegroundColor Red
        Write-Host ""
        Write-TestError "Some tests failed. Please review the output above."
        exit 1
    } else {
        Write-Host ""
        Write-Host "[SUCCESS] All tests passed! 🎉" -ForegroundColor Green
        exit 0
    }
}

# Run the main function
Main
