# Whitty Hybrid — one-command activation for Windows
# Usage:  $env:BRIDGE_TOKEN="xxxx"; powershell -ExecutionPolicy Bypass -File scripts\activate.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
Write-Host "⚡ Whitty Hybrid — activating local Hands" -ForegroundColor Cyan

try { $py = (Get-Command python).Source } catch { Write-Host "❌ Python 3 not found. Install from python.org (check 'Add to PATH')." -ForegroundColor Red; exit 1 }

Set-Location daemon
if (-not (Test-Path .venv)) { & $py -m venv .venv }
& .\.venv\Scripts\Activate.ps1
pip install -q -r requirements.txt

if (-not $env:BRIDGE_TOKEN) { $env:BRIDGE_TOKEN = Read-Host "Paste your BRIDGE_TOKEN (Vercel → Settings → Environment Variables)" }

Write-Host "▶ starting daemon on :8765 ..." -ForegroundColor Yellow
$daemon = Start-Process -FilePath "python" -ArgumentList "main.py" -PassThru -NoNewWindow
Start-Sleep -Seconds 3

$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cf) {
  Write-Host "cloudflared not found. Install it (winget install Cloudflare.cloudflared) or use LAN mode:" -ForegroundColor Yellow
  Write-Host "   In the web app, set the PC URL to http://<your-lan-ip>:8765"
} else {
  Write-Host "▶ opening public tunnel ..." -ForegroundColor Yellow
  $log = Join-Path $env:TEMP "whitty-tunnel.log"
  $tunnel = Start-Process -FilePath "cloudflared" -ArgumentList "tunnel --url http://localhost:8765" -PassThru -NoNewWindow -RedirectStandardError $log
  Start-Sleep -Seconds 10
  $url = (Select-String -Path $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches |
          ForEach-Object { $_.Matches.Value } | Select-Object -First 1)
  Write-Host ""
  Write-Host "==============================================================" -ForegroundColor Green
  Write-Host "✅ Paste this into the web app → 'Connect my PC' → Save & Test:" -ForegroundColor Green
  Write-Host "   $url" -ForegroundColor White
  Write-Host "==============================================================" -ForegroundColor Green
  Write-Host "Press Ctrl+C to stop the tunnel and daemon."
  Wait-Process -Id $daemon.Id
  Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue
}
