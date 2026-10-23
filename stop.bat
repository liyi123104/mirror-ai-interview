@echo off
cd /d "%~dp0"
title mirror - stopping
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\stop-all.ps1"
echo.
pause
