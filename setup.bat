@echo off
rem The Driveway Butler - setup. Double-click me.
title Driveway Butler Setup
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc\setup.ps1"
echo.
echo Press any key to close this window.
pause >nul
