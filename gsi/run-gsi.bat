@echo off
REM Double-click before streaming: starts the CS2 live stats server.
REM Leave the window open while you stream. Close it to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gsi-server.ps1"
pause
