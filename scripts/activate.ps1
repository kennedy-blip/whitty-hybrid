# Whitty Hybrid - one-command activation for Windows
#   .\scripts\activate.ps1        (or .\whitty.ps1)
# Token comes from $env:BRIDGE_TOKEN, daemon\.env, or an interactive prompt.
# Force a specific interpreter with:  $env:WHITTY_PYTHON="C:\Python313\python.exe"
$ErrorActionPreference = "Continue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $scriptDir "..")).Path
$daemonDir = Join-Path $root "daemon"
Set-Location $root

Write-Host ""
Write-Host "  Whitty Hybrid - activating local Hands" -ForegroundColor Cyan
Write-Host "  repo: $root" -ForegroundColor DarkGray

function Get-PyVersion([string]$exe) {
  try { return (& $exe -c "import sys;print('%d.%d' % sys.version_info[:2])" 2>$null) } catch { return $null }
}

function Test-Venv([string]$dir) {
  if (-not (Test-Path -LiteralPath $dir)) { return $false }
  $pyExe = Join-Path (Join-Path $dir "Scripts") "python.exe"
  $cfg = Join-Path $dir "pyvenv.cfg"
  return ((Test-Path -LiteralPath $pyExe) -and (Test-Path -LiteralPath $cfg))
}

# ---------- 0. preflight: current checkout? ----------
$branch = ""
try { $branch = (& git rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim() } catch { $branch = "" }
if ($branch -and $branch -ne "main") {
  Write-Host "  ! You are on branch '$branch'. 'main' carries the newest daemon code." -ForegroundColor Yellow
  Write-Host "    Switch with:  git checkout main; git pull" -ForegroundColor Yellow
}
$reqPath = Join-Path $daemonDir "requirements.txt"
if (Test-Path -LiteralPath $reqPath) {
  if (Select-String -LiteralPath $reqPath -Pattern '^\s*pydantic==2\.(9|1[01])' -Quiet) {
    Write-Host ""
    Write-Host "  X This checkout still has the OLD pinned requirements (pydantic==2.9.x)." -ForegroundColor Red
    Write-Host "    Those have no wheel for Python 3.13/3.14, so pip tries to build Rust and fails." -ForegroundColor Red
    Write-Host "    Fix - update the code first, then rerun:" -ForegroundColor White
    Write-Host "        git checkout main" -ForegroundColor White
    Write-Host "        git pull" -ForegroundColor White
    Write-Host "        .\scripts\activate.ps1" -ForegroundColor White
    exit 1
  }
}

# ---------- 1. pick a Python ----------
$py = $null
if ($env:WHITTY_PYTHON) {
  if (Test-Path -LiteralPath $env:WHITTY_PYTHON) { $py = $env:WHITTY_PYTHON }
  else { Write-Host "  ! WHITTY_PYTHON points to a missing file - ignoring" -ForegroundColor Yellow }
}
if (-not $py) {
  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher) {
    foreach ($v in @("-3.13", "-3.12", "-3.11")) {
      $cand = & $pyLauncher.Source $v -c "import sys;print(sys.executable)" 2>$null
      if ($LASTEXITCODE -eq 0 -and $cand) { $py = ($cand | Out-String).Trim(); break }
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
  Write-Host "    Install Python 3.12 or 3.13 from https://python.org/downloads (tick 'Add python.exe to PATH')." -ForegroundColor Yellow
  Write-Host "    Then open a NEW PowerShell window and rerun this script." -ForegroundColor Yellow
  exit 1
}
$pyVer = Get-PyVersion $py
Write-Host "  python: $py ($pyVer)" -ForegroundColor DarkGray

$parts = "$pyVer".Split(".")
$major = [int]$parts[0]
$minor = [int]$parts[1]
if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 9)) {
  Write-Host "  X Python $pyVer is too old - 3.9 or newer required." -ForegroundColor Red
  exit 1
}
if ($major -eq 3 -and $minor -ge 15) {
  Write-Host "  ! Python $pyVer is newer than the published wheels - install may fail." -ForegroundColor Yellow
  Write-Host "    If it does, install 3.13 and set `$env:WHITTY_PYTHON to its python.exe" -ForegroundColor Yellow
}

# ---------- 2. token ----------
if (-not $env:BRIDGE_TOKEN) {
  $envFile = Join-Path $daemonDir ".env"
  if (Test-Path -LiteralPath $envFile) {
    Get-Content -LiteralPath $envFile | ForEach-Object {
      if ($_ -match '^\s*BRIDGE_TOKEN\s*=\s*(.+?)\s*$') { $env:BRIDGE_TOKEN = $Matches[1].Trim('"').Trim("'") }
    }
  }
}
if (-not $env:BRIDGE_TOKEN) {
  Write-Host ""
  Write-Host "  Paste the BRIDGE_TOKEN from Vercel -> whitty-hybrid -> Settings -> Environment Variables" -ForegroundColor Yellow
  $env:BRIDGE_TOKEN = Read-Host "  BRIDGE_TOKEN"
}
if (-not $env:BRIDGE_TOKEN) { Write-Host "  ! No token given - the cloud app will get 401s." -ForegroundColor Red }

# ---------- 3. venv (repairs a damaged or foreign one) ----------
Set-Location $daemonDir
$venvDir = Join-Path $daemonDir ".venv"

if ((Test-Path -LiteralPath $venvDir) -and -not (Test-Venv $venvDir)) {
  Write-Host "  .venv is damaged (no pyvenv.cfg or python.exe) - repairing" -ForegroundColor Yellow
  & $py -m venv --clear $venvDir 2>$null
  if (-not (Test-Venv $venvDir)) {
    Remove-Item -LiteralPath $venvDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $venvDir) {
      Write-Host "  could not delete .venv (a daemon may be holding its files) - building .venv2 instead" -ForegroundColor Yellow
      Write-Host "    stop the old daemon:  Get-Process python,pythonw -EA SilentlyContinue | Stop-Process -Force" -ForegroundColor Yellow
      $venvDir = Join-Path $daemonDir ".venv2"
    }
    & $py -m venv $venvDir
  }
}

if (Test-Path -LiteralPath $venvDir) {
  $cfg = Join-Path $venvDir "pyvenv.cfg"
  if (Test-Path -LiteralPath $cfg) {
    $raw = Get-Content -LiteralPath $cfg -Raw
    if ($raw -match 'version(?:_info)?\s*=\s*"?(\d+\.\d+)') {
      if ($Matches[1] -ne $pyVer) {
        Write-Host "  existing env uses Python $($Matches[1]) - rebuilding for $pyVer" -ForegroundColor Yellow
        & $py -m venv --clear $venvDir
      }
    }
  }
}

if (-not (Test-Path -LiteralPath $venvDir)) {
  Write-Host "  creating virtualenv ..." -ForegroundColor DarkGray
  & $py -m venv $venvDir
}
if (-not (Test-Venv $venvDir)) {
  Write-Host "  X Could not create a working virtualenv in $venvDir" -ForegroundColor Red
  Write-Host "    Stop any running daemon, delete the folder, and retry:" -ForegroundColor Yellow
  Write-Host "        Get-Process python,pythonw -EA SilentlyContinue | Stop-Process -Force" -ForegroundColor White
  Write-Host "        Remove-Item -Recurse -Force `"$venvDir`"" -ForegroundColor White
  exit 1
}
$venvPy = Join-Path (Join-Path $venvDir "Scripts") "python.exe"

# ---------- 4. dependencies ----------
Write-Host "  installing dependencies (first run ~30s) ..." -ForegroundColor DarkGray
& $venvPy -m pip install --quiet --disable-pip-version-check --upgrade pip 2>$null
& $venvPy -m pip install --disable-pip-version-check --prefer-binary -r (Join-Path $daemonDir "requirements.txt")
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "  X Dependency install failed." -ForegroundColor Red
  Write-Host "    Most common causes:" -ForegroundColor Yellow
  Write-Host "      1) your Python is newer than the published wheels (a source build needs Rust/C)" -ForegroundColor Yellow
  Write-Host "      2) the .venv is damaged or half-deleted (stop any daemon, then delete it)" -ForegroundColor Yellow
  Write-Host "      3) a stale checkout with old pins - run: git checkout main; git pull" -ForegroundColor Yellow
  Write-Host "    Try a clean env with a known-good interpreter:" -ForegroundColor White
  Write-Host "        py -3.13 -m venv --clear `"$venvDir`"" -ForegroundColor White
  Write-Host "        & `"$venvPy`" -m pip install -r requirements.txt" -ForegroundColor White
  Write-Host "    Behind a corporate proxy?  `$env:HTTPS_PROXY='http://host:port'" -ForegroundColor Yellow
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
  Write-Host "    (stop it first if you want this script to manage it)" -ForegroundColor DarkGray
} else {
  Write-Host "  starting daemon on http://localhost:8765 ..." -ForegroundColor Yellow
  $daemon = Start-Process -FilePath $venvPy -ArgumentList "main.py" -PassThru -NoNewWindow
  Start-Sleep -Seconds 4
  if ($daemon.HasExited) {
    Write-Host "  X daemon exited right away. Usual causes:" -ForegroundColor Red
    Write-Host "     - port 8765 already taken by another daemon" -ForegroundColor Yellow
    Write-Host "     - run it in the foreground to see the real error:" -ForegroundColor Yellow
    Write-Host "         cd `"$daemonDir`"; & `"$venvPy`" main.py" -ForegroundColor White
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
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
$tunnel = Start-Process -FilePath $cf.Source -ArgumentList "tunnel", "--url", "http://localhost:8765" -PassThru -NoNewWindow -RedirectStandardError $log

$url = $null
for ($i = 0; $i -lt 30 -and -not $url; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path -LiteralPath $log) {
    $url = (Select-String -LiteralPath $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches -ErrorAction SilentlyContinue |
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
