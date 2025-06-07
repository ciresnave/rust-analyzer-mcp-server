@echo off
REM Rust Analyzer MCP Server - Windows Batch Uninstaller

setlocal enabledelayedexpansion

if "%1"=="--help" goto :help
if "%1"=="/?" goto :help

set "SYSTEM_WIDE=false"
set "FORCE=false"

:parse_args
if "%1"=="--system" set "SYSTEM_WIDE=true" & shift & goto :parse_args
if "%1"=="--force" set "FORCE=true" & shift & goto :parse_args
if "%1"=="" goto :start
shift
goto :parse_args

:help
echo Rust Analyzer MCP Server - Windows Batch Uninstaller
echo.
echo Usage:
echo   uninstall.bat              # Remove user installation
echo   uninstall.bat --system     # Remove system-wide installation (requires admin)
echo   uninstall.bat --force      # Skip confirmation prompts
echo.
exit /b 0

:start
echo === Rust Analyzer MCP Server Uninstaller ===
echo.

REM Determine installation directory
if "%SYSTEM_WIDE%"=="true" (
    set "TARGET_DIR=%ProgramFiles%\RustAnalyzerMCP"
    echo [INFO] Removing system-wide installation
) else (
    set "TARGET_DIR=%LOCALAPPDATA%\RustAnalyzerMCP"
    echo [INFO] Removing user installation
)

set "BINARY_PATH=%TARGET_DIR%\rust-analyzer-mcp-server.exe"

REM Check if installation exists
if not exist "%BINARY_PATH%" (
    echo [WARNING] MCP server not found at: %BINARY_PATH%
    echo [INFO] Checking other common locations...
    
    if exist "%LOCALAPPDATA%\RustAnalyzerMCP\rust-analyzer-mcp-server.exe" (
        echo [INFO] Found user installation
        set "TARGET_DIR=%LOCALAPPDATA%\RustAnalyzerMCP"
        set "BINARY_PATH=%TARGET_DIR%\rust-analyzer-mcp-server.exe"
    ) else if exist "%ProgramFiles%\RustAnalyzerMCP\rust-analyzer-mcp-server.exe" (
        echo [INFO] Found system installation
        set "TARGET_DIR=%ProgramFiles%\RustAnalyzerMCP"
        set "BINARY_PATH=%TARGET_DIR%\rust-analyzer-mcp-server.exe"
    ) else (
        echo [ERROR] No installation found. Nothing to uninstall.
        exit /b 1
    )
)

echo [INFO] Found installation at: %BINARY_PATH%

REM Confirmation prompt
if "%FORCE%"=="false" (
    echo.
    echo [WARNING] This will remove the Rust Analyzer MCP Server and its installation directory:
    echo   Directory: %TARGET_DIR%
    echo   Binary: %BINARY_PATH%
    echo.
    set /p "confirmation=Are you sure you want to continue? (y/N): "
    if /i not "!confirmation!"=="y" (
        echo [INFO] Uninstallation cancelled.
        exit /b 0
    )
)

echo.
echo [INFO] Starting uninstallation...

REM Stop any running instances
echo [INFO] Checking for running processes...
tasklist /FI "IMAGENAME eq rust-analyzer-mcp-server.exe" 2>NUL | find /I /N "rust-analyzer-mcp-server.exe" >NUL
if "%ERRORLEVEL%"=="0" (
    echo [INFO] Stopping running MCP server processes...
    taskkill /F /IM rust-analyzer-mcp-server.exe >NUL 2>&1
    echo [SUCCESS] Stopped running processes
)

REM Remove auto-start configuration
echo [INFO] Removing auto-start configuration...
schtasks /query /tn "RustAnalyzerMCPServer" >NUL 2>&1
if "%ERRORLEVEL%"=="0" (
    echo [INFO] Removing scheduled task...
    schtasks /delete /tn "RustAnalyzerMCPServer" /f >NUL 2>&1
    if !errorlevel! equ 0 (
        echo [SUCCESS] Removed scheduled task
    ) else (
        echo [WARNING] Failed to remove scheduled task
    )
) else (
    echo [INFO] No scheduled task found
)

REM Remove the directory and uninstaller
if exist "%TARGET_DIR%" (
    echo [INFO] Removing installation directory...
    rmdir /s /q "%TARGET_DIR%"
    if !errorlevel! equ 0 (
        echo [SUCCESS] Removed installation directory: %TARGET_DIR%
    ) else (
        echo [ERROR] Failed to remove installation directory
        exit /b 1
    )
)

REM Remove this uninstaller if it's in the installation directory
set "CURRENT_SCRIPT=%~f0"
set "SCRIPT_DIR=%~dp0"
if /i "%SCRIPT_DIR:~0,-1%"=="%TARGET_DIR%" (
    echo [INFO] Scheduling removal of uninstaller...
    REM Use a batch file to delete this script after it exits
    echo @echo off > "%TEMP%\cleanup_uninstaller.bat"
    echo timeout /t 2 /nobreak ^>nul >> "%TEMP%\cleanup_uninstaller.bat"
    echo del /f /q "%CURRENT_SCRIPT%" 2^>nul >> "%TEMP%\cleanup_uninstaller.bat"
    echo del /f /q "%TEMP%\cleanup_uninstaller.bat" 2^>nul >> "%TEMP%\cleanup_uninstaller.bat"
    start /b cmd /c "%TEMP%\cleanup_uninstaller.bat"
)

REM Note about PATH (batch scripts have limited PATH manipulation capabilities)
echo.
echo [SUCCESS] Rust Analyzer MCP Server has been successfully uninstalled!
echo.
echo [INFO] Notes:
echo   • You may need to manually remove '%TARGET_DIR%' from your PATH environment variable
echo   • Any MCP client configurations will need to be updated manually
echo   • Auto-start configuration has been removed from Windows Task Scheduler
echo   • Rust and rust-analyzer remain installed (not removed by this uninstaller)
echo   • Restart your terminal/command prompt for changes to take effect
echo.

:end
