@echo off
REM Double-click this to run the OBS setup script (default theme: acid).
REM Pick a different overlay theme by passing it as an argument:
REM   run-setup.bat acid
REM   run-setup.bat printstream
REM   run-setup.bat purple
set THEME=%1
if "%THEME%"=="" set THEME=acid
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0obs-stream-setup.ps1" -Theme %THEME%
