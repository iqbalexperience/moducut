@echo off
cd /d "%~dp0"
if exist "%~dp0ModuCut.exe" (
    start "" "%~dp0ModuCut.exe"
) else (
    echo ModuCut.exe not found in %~dp0
    pause
)