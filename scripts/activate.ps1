# Whitty Hybrid - one-command activation for Windows
#   .\scripts\activate.ps1        (or .\whitty.ps1)
# Token comes from $env:BRIDGE_TOKEN, daemon\.env, or an interactive prompt.
# Force a specific interpreter with:  $env:WHITTY_PYTHON="C:\Python312\python.exe"
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")
$root = Get-Location
Write-Host ""
Write-Host "  Whitty Hybrid - activating local Hands" -ForegroundColor Cyan
Write-Host "  repo: $root" -ForegroundColor DarkGray

# ---------- 0. preflight: is this checkout current? ----------
$branch = ""
try { $branch = (& git rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim() } catch { $branch = "" }
if ($branch -and $branch -ne "main") {
  Write-Host "  ! You are on branch '$branch'. 'main' carries the newest daemon code." -ForegroundColor Yellow
  Write-Host "    Switch with:  git checkout main; git pull" -ForegroundColor Yellow
}
$reqPath = Join-Path $root "daemon
equirements.txt"
if (Test-Path $reqPath) {
  $pinned = Select-String -Path $reqPath -Pattern '^\s*pydantic==2\.(9|1[01])' -Quiet
  if ($pinned) {
    Write-Host ""
    Write-Host "  X This checkout still has the OLD pinned requirements (pydantic==2.9.x)." -ForegroundColor Red
    Write-Host "    Those have no wheel for Python 3.14, so pip tries to compile Rust and fails." -ForegroundColor Red
    Write-Host "    Fix - update the code first, then rerun:" -ForegroundColor White
    Write-Host "        git checkout main" -ForegroundColor White
    Write-Host "        git pull" -ForegroundColor White
    Write-Host "        .\scripts\activate.ps1" -ForegroundColor White
    exit 1
  }
}

function Get-PyVersion($exe) {
  try { return (& $exe -c "import sys;print('%d.%d' % sys.version_info[:2])" 2>$null) } catch { return $null }
}

# ---------- 1. pick a Python ----------
$py = $null
if ($env:WHITTY_PYTHON) {
  if (Test-Path $env:WHITTY_PYTHON) { $py = $env:WHITTY_PYTHON }
  else { Write-Host "  ! WHITTY_PYTHON points to a missing file - ignoring" -ForegroundColor Yellow }
}
if (-not $py) {
  # Prefer a slightly older, thoroughly-supported interpreter when the py launcher has one:
  # brand-new CPython releases are the usual cause of "no wheel, must compile" failures.
  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher) {
    foreach ($v in @("-3.13", "-3.12", "-3.11")) {
      $cand = & $pyLauncher.Source $v -c "import sys;print(sys.executable)" 2>$null
      if ($LASTEXITCODE -eq 0 -and $cand) { $py = $cand.Trim(); break }
    }
  }
}
if (-not $py) {
  foreach ($cand in @("python", "python3", "py")) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source; break }
  }
}
if (-not $py) {
  Write-Host "`n  X Python 3 not found." -ForegroundColor Red
  Write-Host "    Install Python 3.12 or 3.13 from https://python.org/downloads and tick 'Add python.exe to PATH'." -ForegroundColor Yellow
  Write-Host "    Then open a NEW PowerShell window and rerun this script." -ForegroundColor Yellow
  exit 1
}
$pyVer = Get-PyVersion $py
Write-Host "  python: $py ($pyVer)" -ForegroundColor DarkGray

$verParts = $pyVer.Split(".")
$major = [int]$verParts[0]; $minor = [int]$verParts[1]
if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 9)) {
  Write-Host "  X Python $pyVer is too old - 3.9 or newer required." -ForegroundColor Red
  exit 1
}
if ($major -eq 3 -and $minor -ge 15) {
  Write-Host "  ! Python $pyVer is very new - some packages may not have wheels yet." -ForegroundColor Yellow
  Write-Host "    If install fails, install 3.12/3.13 and set WHITTY_PYTHON to its python.exe" -ForegroundColor Yellow
}

# ---------- 2. token ----------
if (-not $env:BRIDGE_TOKEN) {
  $envFile = Join-Path $root "daemon\.env"
  if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
      if ($_ -match '^\s*BRIDGE_TOKEN\s*=\s*(.+?)\s*$') { $env:BRIDGE_TOKEN = $Matches[1].Trim('"').Trim("'") }
    }
  }
}
if (-not $env:BRIDGE_TOKEN) {
  Write-Host "`n  Paste the BRIDGE_TOKEN from Vercel -> whitty-hybrid -> Settings -> Environment Variables" -ForegroundColor Yellow
  $env:BRIDGE_TOKEN = Read-Host "  BRIDGE_TOKEN"
}
if (-not $env:BRIDGE_TOKEN) { Write-Host "  ! No token given - the cloud app will get 401s." -ForegroundColor Red }

# ---------- 3. venv (recreated if it was built by a different Python) ----------
Set-Location (Join-Path $root "daemon")
if (Test-Path ".venv") {
  $cfg = Join-Path (Get-Location) ".venv\pyvenv.cfg"
  $stale = $false
  if (Test-Path $cfg) {
    $raw = Get-Content $cfg -Raw
    if ($raw -match 'version(?:_info)?\s*=\s*"?(\d+\.\d+)') {
      if ($Matches[1] -ne $pyVer) { $stale = $true }
    }
  }
  if ($stale) {
    Write-Host "  existing .venv uses a different Python - rebuilding it" -ForegroundColor Yellow
    Remove-Item -Recurse -Force ".venv"
  }
}
if (-not (Test-Path ".venv")) {
  Write-Host "  creating virtualenv ..." -ForegroundColor DarkGray
  & $py -m venv .venv
  if ($LASTEXITCODE -ne 0) { Write-Host "  X venv creation failed" -ForegroundColor Red; exit 1 }
}
$venvPy = Join-Path (Get-Location) ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) { Write-Host "  X .venv\Scripts\python.exe missing - delete .venv and rerun" -ForegroundColor Red; exit 1 }

# ---------- 4. dependencies ----------
Write-Host "  installing dependencies (first run ~30s) ..." -ForegroundColor DarkGray
& $venvPy -m pip install --quiet --disable-pip-version-check --upgrade pip 2>$null
# --prefer-binary: never build from source when a wheel exists.
& $venvPy -m pip install --disable-pip-version-check --prefer-binary -r requirements.txt
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "  X Dependency install failed." -ForegroundColor Red
  Write-Host "    Most common cause: your Python is newer than the wheels published for it" -ForegroundColor Yellow
  Write-Host "    (a source build then needs a Rust/C compiler). Fix it with either:" -ForegroundColor Yellow
  Write-Host "      1) install Python 3.12 or 3.13, then:" -ForegroundColor White
  Write-Host '           py -3.12 -m venv .venv' -ForegroundColor White
  Write-Host '           .\.venv\Scripts\python.exe -m pip install -r requirements.txt' -ForegroundColor White
  Write-Host "      2) or point this script at it:  `$env:WHITTY_PYTHON='C:\Python312\python.exe'" -ForegroundColor White
  Write-Host "    Behind a corporate proxy?  `$env:HTTPS_PROXY='http://host:port'" -ForegroundColor Yellow
  Write-Host "    Also check you are on main:  git checkout main; git pull   (stale branches carry old pins)" -ForegroundColor Yellow
  Write-Host "    If deleting .venv said 'Access is denied', a daemon is still running and holding" -ForegroundColor Yellow
  Write-Host "    the .dll files. Stop it first:  Get-Process python,pythonw -EA SilentlyContinue | Stop-Process -Force" -ForegroundColor Yellow
  exit 1
}
Write-Host "  dependencies OK" -ForegroundColor Green

# ---------- 5. daemon ----------
$daemon = $null
$alreadyUp = $false
try {
  $h = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 3
  if ($h.StatusCode -eq 200) { $alreadyUp = $true }
} catch { $alreadyUp = $false }

if ($alreadyUp) {
  Write-Host "  a daemon is already answering on :8765 - leaving it alone" -ForegroundColor Green
  Write-Host "    (stop it first if you want this script to manage it: Get-Process python | Stop-Process)" -ForegroundColor DarkGray
} else {
  Write-Host "  starting daemon on http://localhost:8765 ..." -ForegroundColor Yellow
  $daemon = Start-Process -FilePath $venvPy -ArgumentList "main.py" -PassThru -NoNewWindow
  Start-Sleep -Seconds 4
  if ($daemon.HasExited) {
    Write-Host "  X daemon exited right away. Usual causes:" -ForegroundColor Red
    Write-Host "     - port 8765 already taken by another daemon (close it, or it is fine as-is)" -ForegroundColor Yellow
    Write-Host "     - run it in the foreground to see the real error:" -ForegroundColor Yellow
    Write-Host "         cd daemon; .\.venv\Scripts\python.exe main.py" -ForegroundColor White
    exit 1
  }
  try {
    $probe = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "  daemon is healthy (HTTP $($probe.StatusCode))" -ForegroundColor Green
  } catch {
    Write-Host "  ! no answer on /health - check the output above" -ForegroundColor Yellow
  }
}

# ---------- 6. tunnel ----------
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cf) {
  Write-Host ""
  Write-Host "  cloudflared not installed - two options:" -ForegroundColor Yellow
  Write-Host "    a) public:  winget install Cloudflare.cloudflared   then rerun"
  Write-Host "    b) same Wi-Fi only: use  http://<THIS-PC-LAN-IP>:8765  in the web app"
  $lan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
          Select-Object -First 1).IPAddress
  if ($lan) { Write-Host "       this PC looks like:  http://${lan}:8765" -ForegroundColor Cyan }
  Write-Host ""
  Write-Host "  Daemon running. Press Ctrl+C to stop." -ForegroundColor DarkGray
  if ($daemon) { Wait-Process -Id $daemon.Id } else { while ($true) { Start-Sleep -Seconds 3600 } }
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
  Write-Host "   (the URL changes on every restart - just re-paste it)"
} else {
  Write-Host "  ! tunnel URL not found yet, check: $log" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Running. Press Ctrl+C to stop daemon + tunnel." -ForegroundColor DarkGray
if ($daemon) { Wait-Process -Id $daemon.Id } else { while ($true) { Start-Sleep -Seconds 3600 } }
if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -ErrorAction SilentlyContinue }
