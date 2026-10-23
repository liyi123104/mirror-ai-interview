@echo off
cd /d "%~dp0"
title mirror - starting (close this window to stop)
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\start-all.ps1" -WithWeb
echo.
echo [mirror] all services stopped. Press any key to close.
pause >nul
