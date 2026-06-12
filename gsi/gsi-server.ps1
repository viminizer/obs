<#
  gsi-server.ps1
  Tiny local server for the CS2 live stats overlay.
    - CS2 POSTs game state here (configured by gamestate_integration_zevon.cfg)
    - GET /      -> serves stats-overlay.html (the OBS browser source)
    - GET /data  -> latest game state JSON (polled by the overlay)
  Start it with run-gsi.bat before you stream. Ctrl+C or close the window to stop.
#>
$ErrorActionPreference = "Stop"
$port = 3456
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$html = Join-Path $root "stats-overlay.html"

# Premier rating shown on the HUD. Valve exposes it nowhere (not in GSI, no
# API), so it lives in premier-elo.txt next to this script - edit the number
# there whenever your rating changes, the HUD picks it up within a minute.
$premierFile = Join-Path $root "premier-elo.txt"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()
Write-Host "CS2 stats server running on http://127.0.0.1:$port/" -ForegroundColor Green
Write-Host "Leave this window open while streaming. Close it to stop." -ForegroundColor Yellow

$latest = "{}"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
        if ($req.HttpMethod -eq "POST") {
            $reader = New-Object IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $latest = $reader.ReadToEnd()
            $reader.Close()
            $buf = [Text.Encoding]::UTF8.GetBytes("ok")
        }
        elseif ($req.Url.AbsolutePath -eq "/data") {
            $res.ContentType = "application/json"
            $res.Headers.Add("Access-Control-Allow-Origin", "*")
            $buf = [Text.Encoding]::UTF8.GetBytes($latest)
        }
        elseif ($req.Url.AbsolutePath -eq "/premier") {
            $elo = $null
            if (Test-Path $premierFile) {
                $raw = (Get-Content $premierFile -Raw).Trim()
                if ($raw -match '^\d+$' -and [int]$raw -gt 0) { $elo = [int]$raw }
            }
            $res.ContentType = "application/json"
            $res.Headers.Add("Access-Control-Allow-Origin", "*")
            $buf = [Text.Encoding]::UTF8.GetBytes((@{ elo = $elo } | ConvertTo-Json -Compress))
        }
        else {
            $res.ContentType = "text/html"
            $buf = [IO.File]::ReadAllBytes($html)
        }
        $res.ContentLength64 = $buf.Length
        $res.OutputStream.Write($buf, 0, $buf.Length)
    } catch {
        # ignore per-request errors, keep serving
    } finally {
        $res.Close()
    }
}
