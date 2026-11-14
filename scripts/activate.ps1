# Whitty Hybrid — one-command activation for Windows
# Run from the repo root:   .\scripts\activate.ps1
# Token comes from $env:BRIDGE_TOKEN, .\daemon\.env, or an interactive prompt.
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")
$root = Get-Location
Write-Host ""
Write-Host "  Whitty Hybrid - activating local Hands" -ForegroundColor Cyan
Write-Host "  repo: $root" -ForegroundColor DarkGray

# ---------- 1. find Python ----------
$py = $null
foreach ($cand in @("python", "py", "python3")) {
  $cmd = Get-Command $cand -ErrorAction SilentlyContinue
  if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) {
  Write-Host "`n  X Python 3 not found." -ForegroundColor Red
  Write-Host "    Install it from https://python.org/downloads and tick 'Add python.exe to PATH', then reopen PowerShell." -ForegroundColor Yellow
  exit 1
}
try { $ver = & $py --version 2>&1 } catch { $ver = "unknown" }
Write-Host "  python: $ver" -ForegroundColor DarkGray

# ---------- 2. token ----------
if (-not $env:BRIDGE_TOKEN) {
  $envFile = Join-Path $root "daemon\.env"
  if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
      if ($_ -match '^\s*BRIDGE_TOKEN\s*=\s*(.+)\s*$') { $env:BRIDGE_TOKEN = $Matches[1].Trim('"').Trim() }
    }
  }
}
if (-not $env:BRIDGE_TOKEN) {
  Write-Host "`n  Paste the BRIDGE_TOKEN from Vercel -> whitty-hybrid -> Settings -> Environment Variables" -ForegroundColor Yellow
  $env:BRIDGE_TOKEN = Read-Host "  BRIDGE_TOKEN"
}
if (-not $env:BRIDGE_TOKEN) { Write-Host "  X No token given - the cloud app will get 401s." -ForegroundColor Red }

# ---------- 3. venv + deps ----------
Set-Location (Join-Path $root "daemon")
if (-not (Test-Path ".venv")) {
  Write-Host "  creating virtualenv ..." -ForegroundColor DarkGray
  & $py -m venv .venv
  if ($LASTEXITCODE -ne 0) { Write-Host "  X venv creation failed (try: python -m pip install --upgrade virtualenv)" -ForegroundColor Red; exit 1 }
}
$venvPy = Join-Path (Get-Location) ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) { $venvPy = $py }

Write-Host "  installing dependencies (first run takes ~30s) ..." -ForegroundColor DarkGray
& $venvPy -m pip install --quiet --upgrade pip
& $venvPy -m pip install --quiet -r requirements.txt
if ($LASTEXITCODE -ne 0) {
  Write-Host "  X pip install failed. If you are behind a proxy set HTTPS_PROXY, then retry." -ForegroundColor Red
  exit 1
}
Write-Host "  dependencies OK" -ForegroundColor Green

# ---------- 4. start daemon ----------
Write-Host "  starting daemon on http://localhost:8765 ..." -ForegroundColor Yellow
$daemon = Start-Process -FilePath $venvPy -ArgumentList "main.py" -PassThru -NoNewWindow
Start-Sleep -Seconds 4
if ($daemon.HasExited) { Write-Host "  X daemon exited immediately - run 'python main.py' in daemon\ to see why" -ForegroundColor Red; exit 1 }

try {
  $probe = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 5
  Write-Host "  daemon is healthy (HTTP $($probe.StatusCode))" -ForegroundColor Green
} catch {
  Write-Host "  ! daemon did not answer /health - check the window output above" -ForegroundColor Yellow
}

# ---------- 5. tunnel ----------
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cf) {
  Write-Host ""
  Write-Host "  cloudflared not installed - two options:" -ForegroundColor Yellow
  Write-Host "    a) public access:  winget install Cloudflare.cloudflared   then rerun this script"
  Write-Host "    b) same Wi-Fi only: in the web app use  http://<this-PC-LAN-IP>:8765"
  $lan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
          Select-Object -First 1).IPAddress
  if ($lan) { Write-Host "       your LAN IP looks like: http://${lan}:8765" -ForegroundColor Cyan }
  Write-Host ""
  Write-Host "  Daemon is running. Press Ctrl+C to stop it." -ForegroundColor DarkGray
  Wait-Process -Id $daemon.Id
  exit 0
}

Write-Host "  opening public tunnel ..." -ForegroundColor Yellow
$log = Join-Path $env:TEMP "whitty-tunnel.log"
if (Test-Path $log) { Remove-Item $log -Force }
$tunnel = Start-Process -FilePath $cf.Source -ArgumentList "tunnel","--url","http://localhost:8765" -PassThru -NoNewWindow -RedirectStandardError $log

$url = $null
for ($i = 0; $i -lt 30 -and -not $url; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $log) {
    $url = (Select-String -Path $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Matches.Value } | Select-Object -First 1)
  }
}

Write-Host ""
if ($url) {
  Write-Host "  ==============================================================" -ForegroundColor Green
  Write-Host "   Paste this into the app:  Connect my PC  ->  Save & Test" -ForegroundColor Green
  Write-Host "   $url" -ForegroundColor White
  Write-Host "   https://whitty-hybrid.vercel.app" -ForegroundColor DarkGray
  Write-Host "  ==============================================================" -ForegroundColor Green
  Write-Host "   (this URL changes every restart - just re-paste it)"
} else {
  Write-Host "  ! tunnel URL not found yet. Check: $log" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Running. Press Ctrl+C to stop daemon + tunnel." -ForegroundColor DarkGray
Wait-Process -Id $daemon.Id
if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue }
