# Whitty Hybrid - run the daemon in the background, no terminal needed.
#
#   .\scripts\install-service.ps1              install (auto-start at logon)
#   .\scripts\install-service.ps1 -StartNow    install and start immediately
#
# Registers a Scheduled Task that launches pythonw.exe (no console window).
# The token is read from daemon\.env, so create that file first:
#   "BRIDGE_TOKEN=..." | Set-Content .\daemon\.env -Encoding ascii
#
# NOTE: this file is deliberately pure ASCII. Windows PowerShell 5.1 reads
# BOM-less scripts in the system ANSI codepage, so non-ASCII characters (em
# dashes, checkmarks) get mangled and can break the parser.
param(
  [switch]$StartNow,
  [ValidateSet("auto", "highest", "limited")]
  [string]$RunLevel = "auto",
  # Re-launch this script in an elevated window (UAC prompt) and exit.
  [switch]$Elevate
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$daemonDir = Join-Path $root "daemon"
$taskName = "WhittyHybridDaemon"

function Test-Elevated {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

if ($Elevate -and -not (Test-Elevated)) {
  Write-Host "  asking Windows for administrator rights (approve the UAC prompt) ..." -ForegroundColor Yellow
  $cmd = "& '$PSCommandPath' -StartNow"
  Start-Process powershell -Verb RunAs -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
  Write-Host "  An elevated window is opening - read its output there." -ForegroundColor Green
  exit 0
}

if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
  Write-Host "  X Scheduled Tasks cmdlets unavailable (needs Windows 8 / Server 2012+)." -ForegroundColor Red
  exit 1
}

$venvPy = Join-Path $daemonDir ".venv\Scripts\pythonw.exe"
if (-not (Test-Path -LiteralPath $venvPy)) {
  $venvPy = Join-Path $daemonDir ".venv2\Scripts\pythonw.exe"
}
if (-not (Test-Path -LiteralPath $venvPy)) {
  Write-Host "  X pythonw.exe not found under daemon\.venv or daemon\.venv2" -ForegroundColor Red
  Write-Host "    Run .\scripts\activate.ps1 once to build the virtualenv, then retry." -ForegroundColor Yellow
  exit 1
}
Write-Host "  using: $venvPy" -ForegroundColor DarkGray

$envFile = Join-Path $daemonDir ".env"
if (-not (Test-Path -LiteralPath $envFile)) {
  Write-Host "  ! daemon\.env not found - the daemon will REFUSE to start without a token." -ForegroundColor Yellow
  Write-Host "    Create it:  `"BRIDGE_TOKEN=<your token>`" | Set-Content .\daemon\.env -Encoding ascii" -ForegroundColor Yellow
}

$elevated = Test-Elevated
$wanted = $RunLevel
if ($wanted -eq "auto") { $wanted = if ($elevated) { "highest" } else { "limited" } }
if ($wanted -eq "highest" -and -not $elevated) {
  Write-Host "  ! Highest privileges need an elevated PowerShell - falling back to normal." -ForegroundColor Yellow
  $wanted = "limited"
}
$level = if ($wanted -eq "highest") { "Highest" } else { "Limited" }

# Replacing a task that belongs to another user (or was created elevated) also
# needs admin; do not let a failure there abort the install.
$existing = $null
try { $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch { $existing = $null }
if ($existing) {
  Write-Host "  replacing existing task '$taskName'" -ForegroundColor DarkGray
  try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch { }
  try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop } catch {
    Write-Host "  X could not remove the old task (created with admin rights?)." -ForegroundColor Red
    Write-Host "    Run this again from an elevated PowerShell, or delete it in Task Scheduler." -ForegroundColor Yellow
    exit 1
  }
}

$action = New-ScheduledTaskAction -Execute $venvPy -Argument "main.py" -WorkingDirectory $daemonDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel $level
$settingsArgs = @{
  AllowStartIfOnBatteries    = $true
  DontStopIfGoingOnBatteries = $true
  ExecutionTimeLimit         = [TimeSpan]::Zero
  RestartCount               = 3
  RestartInterval            = (New-TimeSpan -Minutes 1)
  StartWhenAvailable         = $true
}
$settings = New-ScheduledTaskSettingsSet @settingsArgs

$registered = $false
try {
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Whitty Hybrid local diagnostics + VPN daemon (http://localhost:8765)" -Force -ErrorAction Stop | Out-Null
  $registered = $true
} catch {
  $msg = $_.Exception.Message
  Write-Host "  X Register-ScheduledTask failed: $msg" -ForegroundColor Red
  if ($msg -match "Access is denied|0x80070005") {
    if (-not $elevated) {
      Write-Host "    -> Rerun with one command; it prompts for admin itself:" -ForegroundColor Yellow
      Write-Host "         .\scripts\install-service.ps1 -StartNow -Elevate" -ForegroundColor White
      Write-Host "    Password/VPN tools need admin anyway, so this is worth doing." -ForegroundColor DarkGray
    } else {
      Write-Host "    -> Even elevated, Task Scheduler said no. Check for a group policy that blocks task creation." -ForegroundColor Yellow
    }
  }
}

if (-not $registered) {
  Write-Host ""
  Write-Host "  Nothing was installed. The daemon is NOT running in the background." -ForegroundColor Red
  Write-Host "  Quick alternative while you sort that out - start it in this window:" -ForegroundColor Yellow
  Write-Host "     cd $daemonDir" -ForegroundColor White
  Write-Host "     .\.venv\Scripts\python.exe main.py" -ForegroundColor White
  exit 1
}

Write-Host "  OK registered task '$taskName' (run level: $level)" -ForegroundColor Green
if ($level -eq "limited") {
  Write-Host "  note: without elevation, revealing saved Wi-Fi passwords and WireGuard setup" -ForegroundColor DarkGray
  Write-Host "        will fail. Rerun from an elevated PowerShell to unlock those." -ForegroundColor DarkGray
}

if ($StartNow) {
  try {
    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
  } catch {
    Write-Host "  ! could not start the task: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
  }
  $healthy = $false
  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 2
    try {
      $r = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 4
      Write-Host "  daemon healthy (HTTP $($r.StatusCode)) - runs without a terminal from now on" -ForegroundColor Green
      $healthy = $true
      break
    } catch { }
  }
  if (-not $healthy) {
    Write-Host "  ! no answer on http://localhost:8765/health after 20s." -ForegroundColor Yellow
    Write-Host "    Task Scheduler > $taskName > Last Run Result:" -ForegroundColor Yellow
    Write-Host "      0x0   = still starting / already running" -ForegroundColor DarkGray
    Write-Host "      0x1   = python crashed - run daemon\main.py in a terminal to see why" -ForegroundColor DarkGray
    Write-Host "    Commonest cause: daemon\.env missing or no BRIDGE_TOKEN in it." -ForegroundColor Yellow
  }
} else {
  Write-Host "  It starts automatically the next time you log in." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Manage it:" -ForegroundColor DarkGray
Write-Host "    Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "    Stop-ScheduledTask  -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "    Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false" -ForegroundColor DarkGray
