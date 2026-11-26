@echo off
rem The Driveway Butler - transcribe audio or video. Drag a file onto this icon, or double-click and type the path.
title Driveway Butler - Transcribe
cd /d "%~dp0"
set "PY=%~dp0pc\.venv\Scripts\python.exe"
if not exist "%PY%" (
  echo Setup has not been run yet. Double-click setup.bat first.
  echo.
  echo Press any key to close this window.
  pause >nul
  exit /b 1
)
if "%~1"=="" (
  echo Drag a video or audio file onto this icon, or paste its full path below.
  echo.
  set /p "FILE=File: "
  call "%PY%" "%~dp0pc\transcribe.py" "%FILE%"
) else (
  "%PY%" "%~dp0pc\transcribe.py" %*
)
echo.
echo Press any key to close this window.
pause >nul
