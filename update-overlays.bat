@echo off
REM Copies overlay HTML files into OBS without touching profile, scenes,
REM or plugins. Use this after editing overlay text/colors, or after git pull,
REM when everything else is already set up.
REM
REM Usage (same themes as run-setup.bat, default: acid):
REM   update-overlays.bat
REM   update-overlays.bat printstream
REM   update-overlays.bat purple
REM
REM Then in OBS: right-click the overlay source -> Refresh (or switch scenes
REM if "Refresh browser when scene becomes active" is on).

set THEME=%1
if "%THEME%"=="" set THEME=acid

if /i "%THEME%"=="purple" (
    set SRC=%~dp0overlays
) else (
    set SRC=%~dp0overlays\%THEME%
)

if not exist "%SRC%\webcam-frame.html" (
    echo Theme "%THEME%" not found at %SRC%
    echo Valid themes: acid, printstream, purple
    pause
    exit /b 1
)

if not exist "%APPDATA%\obs-studio\overlays" mkdir "%APPDATA%\obs-studio\overlays"
copy /Y "%SRC%\*.html" "%APPDATA%\obs-studio\overlays\" >nul
echo [ok] %THEME% overlays copied to %APPDATA%\obs-studio\overlays

if exist "%~dp0gsi\stats-overlay.html" (
    if not exist "%APPDATA%\obs-studio\gsi" mkdir "%APPDATA%\obs-studio\gsi"
    copy /Y "%~dp0gsi\stats-overlay.html" "%APPDATA%\obs-studio\gsi\" >nul
    echo [ok] CS2 stats overlay copied to %APPDATA%\obs-studio\gsi
)

echo.
echo Done. In OBS: right-click each overlay source ^> Refresh.
pause
