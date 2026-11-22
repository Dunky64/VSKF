@echo off
rem The Driveway Butler - diagnose. Double-click me.
title Driveway Butler Diagnose
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc\diagnose.ps1"
echo.
echo Press any key to close this window.
pause >nul
