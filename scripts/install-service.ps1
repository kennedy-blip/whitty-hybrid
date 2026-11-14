# Whitty Hybrid - run the daemon in the background, no terminal needed.
#
#   .\scripts\install-service.ps1              install (auto-start at logon)
#   .\scripts\install-service.ps1 -StartNow    install and start immediately
#
# Registers a Scheduled Task that launches pythonw.exe (no console window).
# The token is read from daemon\.env, so create that file first:
#   BRIDGE_TOKEN=b6b8d9818bd3791d4903a7b9e3a723ec
#
# NOTE: this file is deliberately pure ASCII. Windows PowerShell 5.1 reads
# BOM-less scripts in the system ANSI codepage, so non-ASCII characters (em
# dashes, checkmarks) get mangled and can break the parser.
param([switch]$StartNow)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$daemonDir = Join-Path $root "daemon"
$venvPy = Join-Path $daemonDir ".venv\Scripts\pythonw.exe"
$taskName = "WhittyHybridDaemon"

if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
  Write-Host "  X Scheduled Tasks cmdlets unavailable (needs Windows 8 / Server 2012+)." -ForegroundColor Red
  exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "  replacing existing task '$taskName'" -ForegroundColor DarkGray
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

if (-not (Test-Path -LiteralPath $venvPy)) {
  $venvPy = Join-Path $root "daemon\.venv2\Scripts\pythonw.exe"
}
if (-not (Test-Path -LiteralPath $venvPy)) {
  Write-Host "  X pythonw.exe not found under daemon\.venv or daemon\.venv2" -ForegroundColor Red
  Write-Host "    Run .\scripts\activate.ps1 once to build the virtualenv, then retry." -ForegroundColor Yellow
  exit 1
}
Write-Host "  using: $venvPy" -ForegroundColor DarkGray

$envFile = Join-Path $daemonDir ".env"
if (-not (Test-Path -LiteralPath $envFile)) {
  Write-Host "  ! daemon\.env not found - the daemon would start without a token." -ForegroundColor Yellow
  Write-Host "    Create it with one line:  BRIDGE_TOKEN=<your token>" -ForegroundColor Yellow
}

$action = New-ScheduledTaskAction -Execute $venvPy -Argument "main.py" -WorkingDirectory $daemonDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
# Highest privileges so WireGuard + "netsh wlan ... key=clear" work without prompts.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settingsArgs = @{
  AllowStartIfOnBatteries    = $true
  DontStopIfGoingOnBatteries = $true
  ExecutionTimeLimit         = [TimeSpan]::Zero
  RestartCount               = 3
  RestartInterval            = (New-TimeSpan -Minutes 1)
  StartWhenAvailable         = $true
}
$settings = New-ScheduledTaskSettingsSet @settingsArgs

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Whitty Hybrid local diagnostics + VPN daemon (http://localhost:8765)" -Force | Out-Null
Write-Host "  OK installed scheduled task '$taskName'" -ForegroundColor Green

if ($StartNow) {
  Start-ScheduledTask -TaskName $taskName
  Start-Sleep -Seconds 4
  $ok = $false
  try {
    $p = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 6
    Write-Host "  daemon healthy (HTTP $($p.StatusCode))" -ForegroundColor Green
    $ok = $true
  } catch {
    Write-Host "  ! no answer on http://localhost:8765/health yet." -ForegroundColor Yellow
    Write-Host "    Task Scheduler > $taskName > Last Run Result will say why" -ForegroundColor Yellow
    Write-Host "    (0x0 = running fine, 0x1 = python crashed, check daemon\.env)" -ForegroundColor DarkGray
  }
  if ($ok) {
    Write-Host "  The daemon keeps running after you close this window." -ForegroundColor DarkGray
  }
} else {
  Write-Host "  It starts automatically the next time you log in." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Manage it:" -ForegroundColor DarkGray
Write-Host "    Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "    Stop-ScheduledTask  -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "    Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Tunnel: use .\scripts\install-tunnel.ps1 -Mode tailscale for a stable" -ForegroundColor DarkGray
Write-Host "  https://<pc>.<tailnet>.ts.net URL that also survives reboots." -ForegroundColor DarkGray
