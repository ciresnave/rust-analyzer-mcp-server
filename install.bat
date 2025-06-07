@echo off
setlocal enabledelayedexpansion

REM Rust Analyzer MCP Server - Windows Batch Installer
REM For users who prefer batch files over PowerShell

echo === Rust Analyzer MCP Server - Windows Installer ===
echo.

REM Check if help was requested
if "%1"=="--help" goto :help
if "%1"=="/?" goto :help
if "%1"=="-h" goto :help

REM Parse command line arguments
set SYSTEM_INSTALL=0
set AUTO_START=0

:parse_args
if "%1"=="--system" (
    set SYSTEM_INSTALL=1
    shift
    goto :parse_args
)
if "%1"=="--auto-start" (
    set AUTO_START=1
    shift
    goto :parse_args
)
if not "%1"=="" (
    echo Unknown option: %1
    echo Use --help for usage information
    exit /b 1
)

goto :main

REM Check for Rust installation
where rustc >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Rust is not installed or not in PATH
    echo Please install Rust from https://rustup.rs/
    exit /b 1
)

for /f "tokens=*" %%i in ('rustc --version 2^>nul') do set RUST_VERSION=%%i
echo [OK] Rust found: !RUST_VERSION!

REM Check for rust-analyzer
where rust-analyzer >nul 2>&1
if !errorlevel! neq 0 (
    echo [WARN] rust-analyzer not found in PATH
    echo Installing rust-analyzer via rustup...
    rustup component add rust-analyzer
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to install rust-analyzer
        exit /b 1
    )
    echo [OK] rust-analyzer installed successfully
) else (
    for /f "tokens=*" %%i in ('rust-analyzer --version 2^>nul') do set RA_VERSION=%%i
    echo [OK] rust-analyzer found: !RA_VERSION!
)

REM Determine installation directory
if !SYSTEM_INSTALL!==1 (
    set INSTALL_DIR=%ProgramFiles%\RustAnalyzerMCP
    set NEEDS_ADMIN=1
) else (
    set INSTALL_DIR=%LOCALAPPDATA%\RustAnalyzerMCP
    set NEEDS_ADMIN=0
)

echo [INFO] Installing to: !INSTALL_DIR!

REM Create installation directory
if not exist "!INSTALL_DIR!" (
    mkdir "!INSTALL_DIR!" 2>nul
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to create installation directory
        if !NEEDS_ADMIN! equ 1 (
            echo Please run this script as Administrator for system-wide installation
        )
        exit /b 1
    )
    echo [OK] Created installation directory
)

REM Build the project
echo [INFO] Building Rust Analyzer MCP Server...
cargo build --release
if !errorlevel! neq 0 (
    echo [ERROR] Failed to build project
    exit /b 1
)
echo [OK] Build completed successfully

REM Copy binary
copy "target\release\rust-analyzer-mcp-server.exe" "!INSTALL_DIR!\" >nul
if !errorlevel! neq 0 (
    echo [ERROR] Failed to copy binary
    exit /b 1
)
echo [OK] Binary copied to !INSTALL_DIR!\rust-analyzer-mcp-server.exe

REM Add to PATH
echo [INFO] Adding to PATH...
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set CURRENT_PATH=%%b
if "!CURRENT_PATH!"=="" set CURRENT_PATH=

echo !CURRENT_PATH! | findstr /i "!INSTALL_DIR!" >nul
if !errorlevel! neq 0 (
    if "!CURRENT_PATH!"=="" (
        set NEW_PATH=!INSTALL_DIR!
    ) else (
        set NEW_PATH=!CURRENT_PATH!;!INSTALL_DIR!
    )
    
    reg add "HKCU\Environment" /v PATH /t REG_EXPAND_SZ /d "!NEW_PATH!" /f >nul
    if !errorlevel! equ 0 (
        echo [OK] Added to PATH
        echo [WARN] Please restart your command prompt to use the command
    ) else (
        echo [ERROR] Failed to add to PATH
        echo Please manually add '!INSTALL_DIR!' to your PATH environment variable
    )
) else (
    echo [OK] Installation directory already in PATH
)

REM Test installation
echo [INFO] Testing installation...
set PATH=!INSTALL_DIR!;!PATH!
"!INSTALL_DIR!\rust-analyzer-mcp-server.exe" --version >nul 2>&1
if !errorlevel! equ 0 (
    for /f "tokens=*" %%i in ('"!INSTALL_DIR!\rust-analyzer-mcp-server.exe" --version 2^>nul') do set VERSION_OUTPUT=%%i
    echo [OK] Installation test passed: !VERSION_OUTPUT!
) else (
    echo [ERROR] Installation test failed
    exit /b 1
)

REM Install uninstaller
echo [INFO] Installing uninstaller...
copy "uninstall.bat" "!INSTALL_DIR!\rust-analyzer-mcp-server-uninstall.bat" >nul 2>&1
if !errorlevel! equ 0 (
    echo [OK] Uninstaller installed: !INSTALL_DIR!\rust-analyzer-mcp-server-uninstall.bat
) else (
    echo [WARN] Could not install uninstaller
)

REM Set up auto-start if requested
if !AUTO_START!==1 (
    echo [INFO] Setting up auto-start at system boot...
    if !SYSTEM_INSTALL!==1 (
        REM System-wide auto-start using Task Scheduler
        schtasks /create /tn "RustAnalyzerMCPServer" /tr "\"!INSTALL_DIR!\rust-analyzer-mcp-server.exe\" ." /sc onstart /ru SYSTEM /f >nul 2>&1
        if !errorlevel! equ 0 (
            echo [OK] Auto-start configured: Task Scheduler - RustAnalyzerMCPServer
        ) else (
            echo [WARN] Could not set up auto-start via Task Scheduler
        )
    ) else (
        REM User auto-start using startup folder
        set STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
        echo @echo off > "!STARTUP_FOLDER!\Rust Analyzer MCP Server.bat"
        echo "!INSTALL_DIR!\rust-analyzer-mcp-server.exe" . >> "!STARTUP_FOLDER!\Rust Analyzer MCP Server.bat"
        if !errorlevel! equ 0 (
            echo [OK] Auto-start configured: Startup folder
        ) else (
            echo [WARN] Could not set up auto-start in startup folder
        )
    )
)

echo.
echo === Installation Complete ===
echo.
echo [OK] Rust Analyzer MCP Server installed successfully!
echo [INFO] Location: !INSTALL_DIR!\rust-analyzer-mcp-server.exe
echo [INFO] Uninstaller: !INSTALL_DIR!\rust-analyzer-mcp-server-uninstall.bat
echo [INFO] Usage: rust-analyzer-mcp-server --help
echo [INFO] For MCP client configuration, see the README.md file
if !AUTO_START!==1 (
    echo [INFO] Auto-start at boot: Enabled
)
echo [WARN] Remember to restart your command prompt to use the 'rust-analyzer-mcp-server' command
goto :end

:help
echo Rust Analyzer MCP Server - Windows Installer
echo.
echo Usage:
echo   install.bat                 # Install to user directory
echo   install.bat --system        # Install system-wide (requires admin)
echo   install.bat --auto-start    # Install and enable auto-start at boot
echo   install.bat --system --auto-start  # System install with auto-start
echo.
echo Options:
echo   --system      Install system-wide (requires Administrator)
echo   --auto-start  Enable auto-start at system boot
echo   --help        Show this help message
echo.

:end
endlocal
