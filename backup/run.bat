@echo off
setlocal
title ModuCut Standalone Editor
cd /d "%~dp0"

:: If called with --launch-window, proceed to the standalone window opener
if "%~1"=="--launch-window" goto :launch_window

echo ========================================================
echo               ModuCut Standalone Editor
echo ========================================================
echo Directory : %~dp0
echo Serving   : http://localhost:3000
echo.
echo Launching ModuCut in standalone window (bypassing Chrome)...
echo Press Ctrl+C in this console window to stop the server.
echo ========================================================
echo.

:: Launch background standalone window opener
start "" /b "%~f0" --launch-window

:: Start the local web server
call npx.cmd serve -l 3000 .
if errorlevel 1 (
    echo [Notice] Falling back to standard npx serve...
    call npx serve -l 3000 .
)

pause
exit /b 0

:launch_window
:: Wait 2-3 seconds for server to start listening
ping 127.0.0.1 -n 3 >nul

:: Detect browser for standalone app mode (prioritizing Edge to bypass Chrome)
set "APP_BROWSER="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "APP_BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined APP_BROWSER if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "APP_BROWSER=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined APP_BROWSER if exist "%LocalAppData%\Microsoft\Edge\Application\msedge.exe" set "APP_BROWSER=%LocalAppData%\Microsoft\Edge\Application\msedge.exe"
if not defined APP_BROWSER if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "APP_BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined APP_BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "APP_BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined APP_BROWSER if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" set "APP_BROWSER=%LocalAppData%\Google\Chrome\Application\chrome.exe"

set "PROFILE_DIR=%LOCALAPPDATA%\ModuCut\Profile"
if not exist "%PROFILE_DIR%" mkdir "%PROFILE_DIR%" >nul 2>&1

if defined APP_BROWSER (
    start "" "%APP_BROWSER%" --app=http://localhost:3000 --user-data-dir="%PROFILE_DIR%" --name="ModuCut" --window-size=1440,900 --hide-crash-restore-bubble --no-first-run --no-default-browser-check
) else (
    start http://localhost:3000
)
exit /b 0