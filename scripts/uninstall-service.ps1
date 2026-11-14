# Remove the background daemon task installed by install-service.ps1
$taskName = "WhittyHybridDaemon"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) { Write-Host "  No scheduled task named '$taskName' found." -ForegroundColor Yellow; exit 0 }
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
Write-Host "  OK Removed '$taskName' - the daemon will no longer start at logon." -ForegroundColor Green
