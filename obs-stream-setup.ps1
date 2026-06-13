<#
  obs-stream-setup.ps1
  One-shot OBS streaming setup for a Windows + NVIDIA gaming/coding stream
  (YouTube via Restream).

  What it does:
    1.  Self-elevates to Administrator.
    2.  Closes OBS if it is running (configs are only safe to edit when closed).
    3.  Downloads + installs the maintained pro plugin stack:
          Move transition, Source Clone, Advanced Scene Switcher.
    4.  Creates a tuned profile "Stream 1080p60 NVENC":
          - NVENC H.264, 1080p60, 9000 kbps CBR (YouTube-friendly)
          - Replay buffer: keeps the last 60s in memory, F10 saves a clip to
            Videos. Auto-starts together with the stream.
          - 60s anti-snipe stream delay.
          - Copies your existing Restream service.json so the stream key is kept.
    5.  Adds the "Stream Kit" scene collection:
          - Scenes: Starting Soon / Gaming / Coding / Just Chatting / BRB.
          - Mic filter chain: Noise Suppression -> Gate -> Compressor -> Limiter.
          - Desktop Audio auto-ducking: game volume dips while you talk.
          - Webcam: forced 1080p 16:9 capture.
          - Animated overlay theme wired in as browser sources (webcam frame,
            in-game HUD, animated background, Starting Soon with live countdown,
            BRB screen). Theme: -Theme acid | printstream | purple (default acid).
          - "Move" animated scene transition as the default.
          - Auto scene switch: focusing the CS2 window switches to Gaming.
    6.  CS2 live stats (Game State Integration):
          - Installs a GSI config into CS2 so the game pushes live state
            (HP, armor, money, K/D/A, round score, bomb) to a tiny local server.
          - Copies the server + stats overlay to %APPDATA%\obs-studio\gsi.
          - The Gaming scene shows the stats top-center, acid-themed.

  Run it (from the folder you saved it in): double-click run-setup.bat
  or:  powershell -ExecutionPolicy Bypass -File .\obs-stream-setup.ps1
  Theme:  run-setup.bat printstream   (acid | printstream | purple)

  -------------------------------------------------------------------------
  MANUAL STEPS (the script cannot do these for you):
    1. After running: open OBS, pick Profile "Stream 1080p60 NVENC" and
       Scene Collection "Stream Kit" from the menus.
    2. Click each device source once to select YOUR hardware:
       Display Capture (monitor), Webcam (camera), Mic / Desktop Audio.
    3. Idle -> BRB rule (one time, ~30s): Tools > Advanced Scene Switcher >
       Idle tab > enable, switch to scene 'BRB' after 120 seconds.
    4. Before each stream: double-click %APPDATA%\obs-studio\gsi\run-gsi.bat
       and leave the window open - that powers the live CS2 stats. No window,
       no stats (the overlay just hides itself, nothing breaks).
    5. Settings > Stream: confirm Restream/YouTube is still connected.
    6. Countdown length: edit COUNTDOWN_MINUTES inside
       %APPDATA%\obs-studio\overlays\starting-soon.html (default 5 min).
  -------------------------------------------------------------------------

  Nothing here is destructive: it only ADDS a new profile + a new scene
  collection. Your current ones are untouched.
#>

param(
    [ValidateSet("acid","printstream","purple")]
    [string]$Theme = "acid"
)

# ---------------------------------------------------------------------------
# 0. Elevate to admin
# ---------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -Theme $Theme"
    exit
}

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Info($m){ Write-Host "  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  [!] $m" -ForegroundColor Yellow }

Write-Host "`n=== OBS stream setup ===`n" -ForegroundColor White

# ---------------------------------------------------------------------------
# 1. Locate OBS
# ---------------------------------------------------------------------------
$obsDir = $null
foreach ($p in @("$env:ProgramFiles\obs-studio", "${env:ProgramFiles(x86)}\obs-studio")) {
    if (Test-Path "$p\bin\64bit\obs64.exe") { $obsDir = $p; break }
}
if (-not $obsDir) {
    # try registry
    try {
        $reg = Get-ItemProperty "HKLM:\SOFTWARE\OBS Studio" -ErrorAction Stop
        if ($reg -and (Test-Path "$($reg.'(default)')\bin\64bit\obs64.exe")) { $obsDir = $reg.'(default)' }
    } catch {}
}
if (-not $obsDir) {
    Warn "Could not find OBS in Program Files. Edit `$obsDir at the top of this script to point at your OBS folder."
    exit 1
}
Ok "OBS found: $obsDir"

$appData = Join-Path $env:APPDATA "obs-studio"
if (-not (Test-Path $appData)) {
    Warn "No OBS config found at $appData. Launch OBS once, then re-run this script."
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Close OBS if running
# ---------------------------------------------------------------------------
$proc = Get-Process obs64 -ErrorAction SilentlyContinue
if ($proc) {
    Info "Closing OBS..."
    $proc | Stop-Process -Force
    Start-Sleep -Seconds 2
    Ok "OBS closed"
}

# ---------------------------------------------------------------------------
# 3. Install plugins
# ---------------------------------------------------------------------------
Write-Host "`n--- Plugins ---" -ForegroundColor White
$tmp = Join-Path $env:TEMP "obs-setup"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# 3a. Inno-Setup installers -> silent install (they auto-detect the OBS path).
# Already-installed plugins (their DLL exists in the OBS folder) are skipped,
# so re-running this script is fast and download-free.
$installers = @(
    @{ Name="Move transition";          Dll="move-transition.dll";          Url="https://github.com/exeldro/obs-move-transition/releases/download/3.2.1/move-transition-3.2.1-windows-installer.exe" },
    @{ Name="Source Clone";             Dll="source-clone.dll";             Url="https://github.com/exeldro/obs-source-clone/releases/download/0.2.3/source-clone-0.2.3-windows-installer.exe" },
    @{ Name="Advanced Scene Switcher";  Dll="advanced-scene-switcher.dll";  Url="https://github.com/WarmUpTill/SceneSwitcher/releases/download/1.34.2/advanced-scene-switcher-1.34.2-windows-x64-Installer.exe" }
)
foreach ($i in $installers) {
    if (Test-Path (Join-Path $obsDir "obs-plugins\64bit\$($i.Dll)")) {
        Ok "$($i.Name) already installed - skipped"
        continue
    }
    $exe = Join-Path $tmp ([IO.Path]::GetFileName($i.Url))
    Info "Downloading $($i.Name)..."
    Invoke-WebRequest -Uri $i.Url -OutFile $exe
    Info "Installing $($i.Name)..."
    Start-Process -FilePath $exe -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait
    Ok "$($i.Name) installed"
}

# ---------------------------------------------------------------------------
# 4. Profile: Stream 1080p60 NVENC
# ---------------------------------------------------------------------------
Write-Host "`n--- Profile ---" -ForegroundColor White
$profileName = "Stream 1080p60 NVENC"
$profileDir  = Join-Path $appData "basic\profiles\Stream 1080p60 NVENC"
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$basicIni = @"
[General]
Name=Stream 1080p60 NVENC

[Output]
Mode=Advanced
DelayEnable=true
DelaySec=60
DelayPreserve=true

[AdvOut]
ApplyServiceSettings=true
Encoder=obs_nvenc_h264_tex
TrackIndex=1
RecType=Standard
RecEncoder=obs_nvenc_h264_tex
RecFilePath=$env:USERPROFILE\Videos
RecFormat2=mp4
RecTracks=1
AudioEncoder=ffmpeg_aac
RecAudioEncoder=ffmpeg_aac
RecRB=true
RecRBTime=60
RecRBSize=512

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=60
ScaleType=bicubic
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Audio]
SampleRate=48000
ChannelSetup=Stereo

[Hotkeys]
ReplayBuffer={"ReplayBuffer.Save": [{"key": "OBS_KEY_F10"}]}
"@
$noBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $profileDir "basic.ini"), $basicIni, $noBom)

# NVENC stream encoder settings (new OBS NVENC, quality-tuned, 9000 kbps CBR
# for YouTube - it has no 6000 cap like Twitch and transcodes everything anyway)
$streamEncoder = @"
{
    "rate_control": "CBR",
    "bitrate": 9000,
    "keyint_sec": 2,
    "preset2": "p5",
    "tune": "hq",
    "multipass": "qres",
    "profile": "high",
    "lookahead": false,
    "psycho_aq": true,
    "gpu": 0,
    "bf": 2
}
"@
[IO.File]::WriteAllText((Join-Path $profileDir "streamEncoder.json"), $streamEncoder, $noBom)
[IO.File]::WriteAllText((Join-Path $profileDir "recordEncoder.json"), $streamEncoder, $noBom)

# Copy the most-recent existing service.json so Restream + stream key carry over
$svc = Get-ChildItem (Join-Path $appData "basic\profiles") -Recurse -Filter "service.json" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($svc) {
    Copy-Item $svc.FullName (Join-Path $profileDir "service.json") -Force
    Ok "Profile created (Restream service copied from $($svc.Directory.Name))"
} else {
    Warn "Profile created, but no existing service.json found - set Restream under Settings > Stream."
}

# Auto-start the replay buffer whenever the stream starts (global OBS setting,
# lives in user.ini on new OBS, global.ini on older versions)
foreach ($iniName in @("user.ini","global.ini")) {
    $ini = Join-Path $appData $iniName
    if (-not (Test-Path $ini)) { continue }
    $txt = [IO.File]::ReadAllText($ini)
    if ($txt -notmatch "ReplayBufferWhileStreaming") {
        if ($txt -match "\[BasicWindow\]") {
            $txt = $txt -replace "\[BasicWindow\]", "[BasicWindow]`r`nReplayBufferWhileStreaming=true"
        } else {
            $txt += "`r`n[BasicWindow]`r`nReplayBufferWhileStreaming=true`r`n"
        }
        [IO.File]::WriteAllText($ini, $txt, $noBom)
        Ok "Replay buffer set to auto-start with the stream ($iniName)"
    }
    break
}

# ---------------------------------------------------------------------------
# 5. Scene collection: Stream Kit
# ---------------------------------------------------------------------------
Write-Host "`n--- Scenes ---" -ForegroundColor White
$sceneDir = Join-Path $appData "basic\scenes"
New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null

# Copy the overlay HTML files (shipped next to this script) into a stable OBS
# folder, so the browser sources keep working even if you move the repo later.
# The purple set lives directly in overlays\, the others in their own subfolder.
Info "Overlay theme: $Theme"
$overlaySrc = if ($Theme -eq "purple") { Join-Path $PSScriptRoot "overlays" }
              else { Join-Path $PSScriptRoot "overlays\$Theme" }
$overlayDest = Join-Path $appData "overlays"
New-Item -ItemType Directory -Force -Path $overlayDest | Out-Null
if (Test-Path (Join-Path $overlaySrc "webcam-frame.html")) {
    Copy-Item (Join-Path $overlaySrc "*.html") $overlayDest -Force
    Ok "Overlays copied to $overlayDest"
} else {
    Warn "overlays\ not found next to the script - put the .html files in $overlayDest yourself."
}
# forward slashes -> valid inside JSON with no escaping needed
$ovl = ($overlayDest -replace '\\','/')
# the CS2 stats overlay is loaded from the gsi folder as a local file, so it
# always loads even if the stats server starts after OBS (it self-heals)
$gsiWeb = (($appData -replace '\\','/') + "/gsi/stats-overlay.html")

$sceneJson = @'
{
  "current_scene": "Gaming",
  "current_program_scene": "Gaming",
  "scene_order": [
    { "name": "Starting Soon" },
    { "name": "Gaming" },
    { "name": "Coding" },
    { "name": "Just Chatting" },
    { "name": "BRB" }
  ],
  "name": "Stream Kit",
  "groups": [],
  "quick_transitions": [
    { "name": "Cut", "duration": 300, "hotkeys": [], "id": 1, "fade_to_black": false },
    { "name": "Fade", "duration": 300, "hotkeys": [], "id": 2, "fade_to_black": false }
  ],
  "transitions": [
    { "name": "Move", "id": "move_transition", "settings": { "duration": 400, "easing_match": 4, "position_in": 4, "position_out": 4, "zoom_in": true, "zoom_out": true } }
  ],
  "transition_duration": 400,
  "transition": "Move",
  "preview_locked": false,
  "scaling_enabled": false,
  "scaling_level": 0,
  "scaling_off_x": 0.0,
  "scaling_off_y": 0.0,
  "virtual-camera": { "type2": 3 },
  "modules": {
    "auto-scene-switcher": {
      "interval": 300,
      "non_matching_scene": "",
      "switch_if_not_matching": false,
      "active": true,
      "switches": [
        { "window": "Counter-Strike 2", "scene": "Gaming" }
      ]
    }
  },
  "sources": [
    {
      "name": "Mic",
      "uuid": "a0000000-0000-4000-8000-000000000004",
      "id": "wasapi_input_capture",
      "versioned_id": "wasapi_input_capture",
      "settings": { "device_id": "default" },
      "mixers": 255, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {},
      "filters": [
        { "name": "Noise Suppression", "uuid": "b0000000-0000-4000-8000-000000000001", "id": "noise_suppress_filter", "versioned_id": "noise_suppress_filter", "settings": { "method": "rnnoise" }, "enabled": true },
        { "name": "Noise Gate", "uuid": "b0000000-0000-4000-8000-000000000002", "id": "noise_gate_filter", "versioned_id": "noise_gate_filter", "settings": { "open_threshold": -26.0, "close_threshold": -32.0, "attack_time": 25, "hold_time": 200, "release_time": 150 }, "enabled": true },
        { "name": "Compressor", "uuid": "b0000000-0000-4000-8000-000000000003", "id": "compressor_filter", "versioned_id": "compressor_filter", "settings": { "ratio": 4.0, "threshold": -18.0, "attack_time": 6, "release_time": 60, "output_gain": 3.0 }, "enabled": true },
        { "name": "Limiter", "uuid": "b0000000-0000-4000-8000-000000000004", "id": "limiter_filter", "versioned_id": "limiter_filter", "settings": { "threshold": -2.0, "release_time": 60 }, "enabled": true }
      ]
    },
    {
      "name": "Desktop Audio",
      "uuid": "a0000000-0000-4000-8000-000000000005",
      "id": "wasapi_output_capture",
      "versioned_id": "wasapi_output_capture",
      "settings": { "device_id": "default" },
      "mixers": 255, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {},
      "filters": [
        { "name": "Ducking", "uuid": "b0000000-0000-4000-8000-000000000006", "id": "compressor_filter", "versioned_id": "compressor_filter", "settings": { "ratio": 8.0, "threshold": -28.0, "attack_time": 6, "release_time": 250, "output_gain": 0.0, "sidechain_source": "Mic" }, "enabled": true }
      ]
    },
    {
      "name": "Webcam",
      "uuid": "a0000000-0000-4000-8000-000000000003",
      "id": "dshow_input",
      "versioned_id": "dshow_input",
      "settings": { "res_type": 1, "resolution": "1920x1080", "last_resolution": "1920x1080" },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Display Capture",
      "uuid": "a0000000-0000-4000-8000-000000000002",
      "id": "monitor_capture",
      "versioned_id": "monitor_capture",
      "settings": { "method": 2 },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "BG",
      "uuid": "a0000000-0000-4000-8000-000000000006",
      "id": "color_source_v3",
      "versioned_id": "color_source_v3",
      "settings": { "color": 4279505454, "width": 1920, "height": 1080 },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Starting Text",
      "uuid": "a0000000-0000-4000-8000-000000000007",
      "id": "text_gdiplus_v2",
      "versioned_id": "text_gdiplus_v2",
      "settings": { "text": "Starting Soon...", "font": { "face": "Arial", "size": 96, "style": "Bold", "flags": 0 } },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "BRB Text",
      "uuid": "a0000000-0000-4000-8000-000000000008",
      "id": "text_gdiplus_v2",
      "versioned_id": "text_gdiplus_v2",
      "settings": { "text": "Be Right Back", "font": { "face": "Arial", "size": 96, "style": "Bold", "flags": 0 } },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Background",
      "uuid": "a0000000-0000-4000-8000-000000000009",
      "id": "browser_source", "versioned_id": "browser_source",
      "settings": { "is_local_file": true, "local_file": "__BG__", "width": 1920, "height": 1080, "restart_when_active": true, "reroute_audio": false },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "HUD",
      "uuid": "a0000000-0000-4000-8000-00000000000a",
      "id": "browser_source", "versioned_id": "browser_source",
      "settings": { "is_local_file": true, "local_file": "__HUD__", "width": 1920, "height": 1080, "restart_when_active": true, "reroute_audio": false },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Webcam Frame",
      "uuid": "a0000000-0000-4000-8000-00000000000b",
      "id": "browser_source", "versioned_id": "browser_source",
      "settings": { "is_local_file": true, "local_file": "__FRAME__", "width": 480, "height": 270, "restart_when_active": true, "reroute_audio": false },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Starting Screen",
      "uuid": "a0000000-0000-4000-8000-00000000000c",
      "id": "browser_source", "versioned_id": "browser_source",
      "settings": { "is_local_file": true, "local_file": "__START__", "width": 1920, "height": 1080, "restart_when_active": true, "reroute_audio": false },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "CS2 Stats",
      "uuid": "a0000000-0000-4000-8000-00000000000e",
      "id": "browser_source", "versioned_id": "browser_source",
      "settings": { "is_local_file": true, "local_file": "__STATS__", "width": 1920, "height": 1080, "restart_when_active": true, "shutdown": false, "reroute_audio": false },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "BRB Screen",
      "uuid": "a0000000-0000-4000-8000-00000000000d",
      "id": "browser_source", "versioned_id": "browser_source",
      "settings": { "is_local_file": true, "local_file": "__BRB__", "width": 1920, "height": 1080, "restart_when_active": true, "reroute_audio": false },
      "mixers": 0, "volume": 1.0, "balance": 0.5, "enabled": true, "muted": false,
      "monitoring_type": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Starting Soon",
      "uuid": "c0000000-0000-4000-8000-000000000001",
      "id": "scene", "versioned_id": "scene",
      "settings": {
        "custom_size": false, "id_counter": 2,
        "items": [
          { "name": "Starting Screen", "source_uuid": "a0000000-0000-4000-8000-00000000000c", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 1 }
        ]
      },
      "mixers": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Gaming",
      "uuid": "c0000000-0000-4000-8000-000000000002",
      "id": "scene", "versioned_id": "scene",
      "settings": {
        "custom_size": false, "id_counter": 8,
        "items": [
          { "name": "Display Capture", "source_uuid": "a0000000-0000-4000-8000-000000000002", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 1 },
          { "name": "Webcam", "source_uuid": "a0000000-0000-4000-8000-000000000003", "visible": true, "locked": false, "pos": { "x": 20.0, "y": 405.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 480.0, "y": 270.0 }, "bounds_align": 0, "id": 2 },
          { "name": "Mic", "source_uuid": "a0000000-0000-4000-8000-000000000004", "visible": true, "locked": false, "id": 3 },
          { "name": "Desktop Audio", "source_uuid": "a0000000-0000-4000-8000-000000000005", "visible": true, "locked": false, "id": 4 },
          { "name": "Webcam Frame", "source_uuid": "a0000000-0000-4000-8000-00000000000b", "visible": true, "locked": false, "pos": { "x": 20.0, "y": 405.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 480.0, "y": 270.0 }, "bounds_align": 0, "id": 5 },
          { "name": "HUD", "source_uuid": "a0000000-0000-4000-8000-00000000000a", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 6 },
          { "name": "CS2 Stats", "source_uuid": "a0000000-0000-4000-8000-00000000000e", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 7 }
        ]
      },
      "mixers": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Coding",
      "uuid": "c0000000-0000-4000-8000-000000000003",
      "id": "scene", "versioned_id": "scene",
      "settings": {
        "custom_size": false, "id_counter": 7,
        "items": [
          { "name": "Display Capture", "source_uuid": "a0000000-0000-4000-8000-000000000002", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 1 },
          { "name": "Webcam", "source_uuid": "a0000000-0000-4000-8000-000000000003", "visible": true, "locked": false, "pos": { "x": 20.0, "y": 405.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 480.0, "y": 270.0 }, "bounds_align": 0, "id": 2 },
          { "name": "Mic", "source_uuid": "a0000000-0000-4000-8000-000000000004", "visible": true, "locked": false, "id": 3 },
          { "name": "Desktop Audio", "source_uuid": "a0000000-0000-4000-8000-000000000005", "visible": true, "locked": false, "id": 4 },
          { "name": "Webcam Frame", "source_uuid": "a0000000-0000-4000-8000-00000000000b", "visible": true, "locked": false, "pos": { "x": 20.0, "y": 405.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 480.0, "y": 270.0 }, "bounds_align": 0, "id": 5 },
          { "name": "HUD", "source_uuid": "a0000000-0000-4000-8000-00000000000a", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 6 }
        ]
      },
      "mixers": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "Just Chatting",
      "uuid": "c0000000-0000-4000-8000-000000000004",
      "id": "scene", "versioned_id": "scene",
      "settings": {
        "custom_size": false, "id_counter": 5,
        "items": [
          { "name": "Background", "source_uuid": "a0000000-0000-4000-8000-000000000009", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 1 },
          { "name": "Webcam", "source_uuid": "a0000000-0000-4000-8000-000000000003", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 2 },
          { "name": "HUD", "source_uuid": "a0000000-0000-4000-8000-00000000000a", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 4 },
          { "name": "Mic", "source_uuid": "a0000000-0000-4000-8000-000000000004", "visible": true, "locked": false, "id": 3 }
        ]
      },
      "mixers": 0, "private_settings": {}, "filters": []
    },
    {
      "name": "BRB",
      "uuid": "c0000000-0000-4000-8000-000000000005",
      "id": "scene", "versioned_id": "scene",
      "settings": {
        "custom_size": false, "id_counter": 2,
        "items": [
          { "name": "BRB Screen", "source_uuid": "a0000000-0000-4000-8000-00000000000d", "visible": true, "locked": false, "pos": { "x": 0.0, "y": 0.0 }, "scale": { "x": 1.0, "y": 1.0 }, "align": 5, "bounds_type": 2, "bounds": { "x": 1920.0, "y": 1080.0 }, "bounds_align": 0, "id": 1 }
        ]
      },
      "mixers": 0, "private_settings": {}, "filters": []
    }
  ]
}
'@
# swap the overlay path placeholders for the real absolute local-file paths
$sceneJson = $sceneJson.
    Replace('__FRAME__', "$ovl/webcam-frame.html").
    Replace('__HUD__',   "$ovl/hud-overlay.html").
    Replace('__BG__',    "$ovl/background.html").
    Replace('__START__', "$ovl/starting-soon.html").
    Replace('__BRB__',   "$ovl/brb.html").
    Replace('__STATS__', "$gsiWeb")

# write UTF-8 without BOM (OBS prefers no BOM)
[IO.File]::WriteAllText((Join-Path $sceneDir "Stream Kit.json"), $sceneJson, (New-Object Text.UTF8Encoding($false)))
Ok "Scene collection 'Stream Kit' created"

# ---------------------------------------------------------------------------
# 6. CS2 live stats (Game State Integration)
# ---------------------------------------------------------------------------
Write-Host "`n--- CS2 live stats ---" -ForegroundColor White
$gsiSrc  = Join-Path $PSScriptRoot "gsi"
$gsiDest = Join-Path $appData "gsi"
if (Test-Path (Join-Path $gsiSrc "gsi-server.ps1")) {
    New-Item -ItemType Directory -Force -Path $gsiDest | Out-Null
    # premier-elo.txt holds your manually-set rating - never overwrite it
    Copy-Item (Join-Path $gsiSrc "*") $gsiDest -Force -Exclude "premier-elo.txt"
    if (-not (Test-Path (Join-Path $gsiDest "premier-elo.txt"))) {
        Copy-Item (Join-Path $gsiSrc "premier-elo.txt") $gsiDest
    }
    Ok "Stats server copied to $gsiDest"

    # find CS2's cfg folder through Steam (checks every Steam library drive)
    $cs2cfg = $null
    $steam = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
    if ($steam) {
        $libs = @($steam)
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += $m.Groups[1].Value.Replace('\\','\')
            }
        }
        foreach ($lib in ($libs | Select-Object -Unique)) {
            $p = Join-Path $lib "steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg"
            if (Test-Path $p) { $cs2cfg = $p; break }
        }
    }
    if ($cs2cfg) {
        Copy-Item (Join-Path $gsiSrc "gamestate_integration_zevon.cfg") $cs2cfg -Force
        Ok "GSI config installed into CS2 ($cs2cfg)"
    } else {
        Warn "CS2 not found. Copy gsi\gamestate_integration_zevon.cfg into your CS2 folder:"
        Warn "  ...\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\"
    }
} else {
    Warn "gsi\ folder not found next to the script - live stats skipped."
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host @"

Next steps in OBS:
  1. Open OBS.
  2. Profile menu        -> select 'Stream 1080p60 NVENC'
  3. Scene Collection    -> select 'Stream Kit'
  4. Click each source once to pick your device:
       - Display Capture (pick the monitor you play / work on)
       - Webcam         (pick your camera)
       - Mic / Desktop Audio (pick devices if not 'Default')
  5. Settings > Stream  -> confirm Restream is still there (it was copied over).
  6. Tools > Advanced Scene Switcher -> add rules if you want auto scene switching.

Mic already has: Noise Suppression -> Gate -> Compressor -> Limiter.
Desktop Audio has auto-ducking: game volume dips while you talk.
Overlays: CS-themed webcam frame, HUD, animated background, Starting Soon
  (with countdown) and BRB screens are already wired into the scenes. To change
  text, edit the .html files in $overlayDest then right-click the source > Refresh.
Replay buffer: auto-starts with the stream. Press F10 to save the last 60s
  (clips land in your Videos folder).
Auto scene switch: focusing CS2 switches to the Gaming scene automatically.
  For idle -> BRB: Tools > Advanced Scene Switcher > Idle tab > enable,
  switch to 'BRB' after 120 seconds. (One-time, takes 30 seconds to set.)
CS2 live stats: double-click $gsiDest\run-gsi.bat before streaming, then the
  Gaming scene shows live HP / money / K-D-A / score pulled from CS2 itself.
Transition: 'Move' animated transition is the default (Move plugin).
Bitrate: 9000 kbps CBR for YouTube.
Stream delay: 60s anti-snipe buffer is on (Settings > Advanced > Stream Delay).
"@ -ForegroundColor White

Read-Host "`nPress Enter to close this window"
