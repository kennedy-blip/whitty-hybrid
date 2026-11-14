# Whitty Hybrid — run the daemon in the background, no terminal needed.
#
#   .\scripts\install-service.ps1              install (auto-start at logon)
#   .\scripts\install-service.ps1 -StartNow    install and start immediately
#
# It registers a Scheduled Task that launches pythonw.exe (no console window).
# The token is read from daemon\.env, so create that file first:
#   BRIDGE_TOKEN=b6b8d9818bd3791d4903a7b9e3a723ec
param([switch]$StartNow)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$daemonDir = Join-Path $root "daemon"
$venvPy = Join-Path $daemonDir ".venv\Scripts\pythonw.exe"
$taskName = "WhittyHybridDaemon"

if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
  $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
}

if (-not (Test-Path $venvPy)) {
  Write-Host "  X pythonw.exe not found at $venvPy" -ForegroundColor Red
  Write-Host "    Run .\scripts\activate.ps1 once to build the virtualenv, then retry." -ForegroundColor Yellow
  exit 1
}
if (-not (Test-Path (Join-Path $daemonDir ".env"))) {
  Write-Host "  ! daemon\.env not found — the daemon would start without a token." -ForegroundColor Yellow
  Write-Host "    Create it with a single line:  BRIDGE_TOKEN=<your token>" -ForegroundColor Yellow
}

$action = New-ScheduledTaskAction -Execute $venvPy -Argument "main.py" -WorkingDirectory $daemonDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
# Run with highest privileges so WireGuard + netsh key=clear work without prompts.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal `
  -Settings $settings -Description "Whitty Hybrid local diagnostics + VPN daemon (http://localhost:8765)" | Out-Null

Write-Host "  ✅ Installed scheduled task '$taskName'" -ForegroundColor Green
if ($StartNow) {
  Start-ScheduledTask -TaskName $taskName
  Start-Sleep -Seconds 4
  try {
    $p = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "  daemon healthy (HTTP $($p.StatusCode))" -ForegroundColor Green
  } catch {
    Write-Host "  ! no answer yet — check Task Scheduler > $taskName > Last Run Result" -ForegroundColor Yellow
  }
} else {
  Write-Host "  It starts automatically the next time you log in."
}
Write-Host ""
Write-Host "  Manage it:" -ForegroundColor DarkGray
Write-Host "    Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "    Stop-ScheduledTask  -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "    Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  NOTE: the daemon now runs without a terminal, but a *quick* Cloudflare tunnel" -ForegroundColor Yellow
Write-Host "  still needs its own process and its URL changes every restart. For an" -ForegroundColor Yellow
Write-Host "  always-on URL, create a free named tunnel (cloudflared tunnel create witty)" -ForegroundColor Yellow
Write-Host "  or install Tailscale and share http://<your-pc>:8765 over your tailnet." -ForegroundColor Yellow
