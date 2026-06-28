@echo off
REM One-click launcher - double-click this file to start the local demo.
REM Passes any extra args through to demo.ps1 (e.g. -Verify, -WithKubernetes, -Down).
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0demo.ps1" %*
echo.
pause
