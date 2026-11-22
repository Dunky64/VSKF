@echo off
rem The Driveway Butler - update. Double-click me.
title Driveway Butler Update
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc\update.ps1"
echo.
echo Press any key to close this window.
pause >nul
