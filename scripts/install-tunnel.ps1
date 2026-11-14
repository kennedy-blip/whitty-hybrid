# Whitty Hybrid - permanent tunnel so the web app can always reach your PC.
#
#   .\scripts\install-tunnel.ps1                          # auto-detect best option
#   .\scripts\install-tunnel.ps1 -Mode tailscale          # *.ts.net, no domain needed
#   .\scripts\install-tunnel.ps1 -Mode cloudflare -Hostname witty.example.com
#
# Unlike a quick tunnel (random *.trycloudflare.com that dies with the window),
# these give a STABLE url that survives reboots and runs as a background service.
param(
  [ValidateSet("auto", "cloudflare", "tailscale")]
  [string]$Mode = "auto",
  [string]$Hostname = "",
  [int]$Port = 8765,
  [switch]$Uninstall
)

$ErrorActionPreference = "Continue"
$taskName = "WhittyHybridTunnel"

function Have([string]$exe) { return [bool](Get-Command $exe -ErrorAction SilentlyContinue) }

# Winget-installed tools aren't on PATH in the session that installed them, so
# resolve the exe from its known install locations instead of making you reopen
# the terminal.
function Resolve-Tool([string]$name, [string[]]$fallbacks) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in $fallbacks) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  return $null
}

function Add-ToolPaths {
  foreach ($dir in @("$env:ProgramFiles\Tailscale", "$env:ProgramFiles\cloudflared", "$env:LOCALAPPDATA\Microsoft\WinGet\Links")) {
    if ((Test-Path -LiteralPath $dir) -and ($env:PATH -notlike "*$dir*")) { $env:PATH = "$env:PATH;$dir" }
  }
}

$tailscalePaths = @(
  "$env:ProgramFiles\Tailscale\tailscale.exe",
  "$env:LOCALAPPDATA\Microsoft\WinGet\Links\tailscale.exe"
)
$cloudflaredPaths = @(
  "$env:ProgramFiles\cloudflared\cloudflared.exe",
  "$env:LOCALAPPDATA\Microsoft\WinGet\Links\cloudflared.exe"
)


if ($Uninstall) {
  if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
  }
  Add-ToolPaths
  $tsReset = Resolve-Tool "tailscale" $tailscalePaths
  if ($tsReset) { & $tsReset funnel reset 2>$null | Out-Null }
  Write-Host "  Tunnel task removed. (Cloudflare tunnel definition kept - delete with: cloudflared tunnel delete witty)" -ForegroundColor Green
  exit 0
}

Write-Host ""
Write-Host "  Whitty Hybrid - permanent tunnel" -ForegroundColor Cyan

# ---------- choose a mode ----------
if ($Mode -eq "auto") {
  if (Have "tailscale") { $Mode = "tailscale" }
  elseif (Have "cloudflared") { $Mode = "cloudflare" }
  else { $Mode = "tailscale" }   # default recommendation: no domain needed
}
Write-Host "  mode: $Mode" -ForegroundColor DarkGray

# ============================================================ TAILSCALE
if ($Mode -eq "tailscale") {
  if (-not (Have "tailscale")) {
    Write-Host "  Tailscale not found." -ForegroundColor Yellow
    if (Have "winget") {
      Write-Host "  Installing: winget install --id Tailscale.Tailscale -e" -ForegroundColor Yellow
      winget install --id Tailscale.Tailscale -e --accept-source-agreements --accept-package-agreements
      Write-Host "  If it installed, CLOSE and REOPEN this terminal, then rerun this script." -ForegroundColor Yellow
    } else {
      Write-Host "  Install from https://tailscale.com/download/windows then rerun." -ForegroundColor Yellow
    }
    exit 1
  }

  Write-Host "  bringing tailscale up (a browser window may open for login) ..." -ForegroundColor Yellow
  $upOk = $false
  for ($try = 1; $try -le 4; $try++) {
    & $tsExe up
    if ($LASTEXITCODE -eq 0) { $upOk = $true; break }
    Write-Host "  (tailscaled may still be starting - retrying in 5s)" -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
  }
  if (-not $upOk) {
    Write-Host "  ! 'tailscale up' kept failing. Check the Tailscale service:" -ForegroundColor Yellow
    Write-Host "      Get-Service Tailscale" -ForegroundColor White
    Write-Host "      Start-Service Tailscale" -ForegroundColor White
    Write-Host "    then rerun this script." -ForegroundColor Yellow
    exit 1
  }

  Write-Host "  enabling Funnel (public HTTPS on your tailnet, no domain needed) ..." -ForegroundColor Yellow
  & $tsExe funnel --bg $Port
  Start-Sleep -Seconds 3
  $status = (& $tsExe funnel status 2>$null | Out-String)
  Write-Host ""
  Write-Host $status

  $url = ([regex]::Match($status, 'https://[a-z0-9-]+\.[a-z0-9.-]*ts\.net')).Value
  Write-Host ""
  if ($url) {
    Write-Host "  ==============================================================" -ForegroundColor Green
    Write-Host "   Permanent URL - paste into the app:  Connect my PC" -ForegroundColor Green
    Write-Host "   $url" -ForegroundColor White
    Write-Host "  ==============================================================" -ForegroundColor Green
  } else {
    Write-Host "  ! Could not read the URL. Run 'tailscale funnel status' and copy the https URL." -ForegroundColor Yellow
    Write-Host "    (Funnel must be enabled for your tailnet: https://login.tailscale.com/admin/acls - add nodeAttrs funnel)" -ForegroundColor Yellow
  }
  Write-Host ""
  Write-Host "  Tailscale runs as a Windows service, so this survives reboots and logout -" -ForegroundColor DarkGray
  Write-Host "  no scheduled task needed. Stop with:  tailscale funnel reset" -ForegroundColor DarkGray
  exit 0
}

# ============================================================ CLOUDFLARE
Add-ToolPaths
$cfExe = Resolve-Tool "cloudflared" $cloudflaredPaths
if (-not $cfExe) {
  Write-Host "  cloudflared not found." -ForegroundColor Yellow
  if (Have "winget") {
    Write-Host "  Installing: winget install --id Cloudflare.cloudflared -e" -ForegroundColor Yellow
    winget install --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements
    Add-ToolPaths
    $cfExe = Resolve-Tool "cloudflared" $cloudflaredPaths
    if ($cfExe) { Write-Host "  installed -> $cfExe (continuing)" -ForegroundColor Green }
  } else {
    Write-Host "  Download cloudflared-windows-amd64.exe from Cloudflare's releases page and put it on PATH." -ForegroundColor Yellow
  }
  if (-not $cfExe) {
    Write-Host "  Still not found. Close and reopen PowerShell, then rerun this script." -ForegroundColor Yellow
    exit 1
  }
}

$cfDir = Join-Path $env:USERPROFILE ".cloudflared"
$cert = Join-Path $cfDir "cert.pem"
$config = Join-Path $cfDir "config.yml"
$tunnelName = "whitty"

if (-not (Test-Path -LiteralPath $cert)) {
  Write-Host "  First-time login: a browser window opens. Pick the domain you want to use." -ForegroundColor Yellow
  & $cfExe tunnel login
  if (-not (Test-Path -LiteralPath $cert)) {
    Write-Host "  X Login did not complete (no cert.pem). Rerun when you can finish the browser step." -ForegroundColor Red
    Write-Host "    A Cloudflare account with a domain is required for named tunnels." -ForegroundColor Yellow
    Write-Host "    No domain? Use Tailscale instead:  .\scripts\install-tunnel.ps1 -Mode tailscale" -ForegroundColor Yellow
    exit 1
  }
}

# create (or reuse) the tunnel
$list = (& $cfExe tunnel list 2>$null | Out-String)
$tunnelId = ""
if ($list -match "(?m)^\S+\s+$tunnelName\s") {
  $tunnelId = ([regex]::Match($list, "(?m)^(\S+)\s+$tunnelName\s")).Groups[1].Value
  Write-Host "  reusing existing tunnel '$tunnelName' ($tunnelId)" -ForegroundColor DarkGray
} else {
  & $cfExe tunnel create $tunnelName
  $list = (& $cfExe tunnel list 2>$null | Out-String)
  $tunnelId = ([regex]::Match($list, "(?m)^(\S+)\s+$tunnelName\s")).Groups[1].Value
}
if (-not $tunnelId) {
  Write-Host "  X Could not create the tunnel. Run 'cloudflared tunnel create witty' manually to see the error." -ForegroundColor Red
  exit 1
}

$creds = Join-Path $cfDir "$tunnelId.json"
if (-not (Test-Path -LiteralPath $creds)) {
  Write-Host "  X Credentials file missing: $creds" -ForegroundColor Red
  exit 1
}

if (-not $Hostname) {
  Write-Host ""
  Write-Host "  Tunnel '$tunnelName' is ready but has no hostname yet." -ForegroundColor Yellow
  Write-Host "  Pick a subdomain of a domain on your Cloudflare account, e.g. witty.mydomain.com," -ForegroundColor Yellow
  Write-Host "  then rerun:" -ForegroundColor Yellow
  Write-Host "      .\scripts\install-tunnel.ps1 -Mode cloudflare -Hostname witty.mydomain.com" -ForegroundColor White
  exit 1
}

Write-Host "  routing $Hostname -> tunnel '$tunnelName' ..." -ForegroundColor Yellow
& $cfExe tunnel route dns $tunnelName $Hostname

$yaml = @"
tunnel: $tunnelId
credentials-file: $creds

ingress:
  - hostname: $Hostname
    service: http://localhost:$Port
  - service: http_status:404
"@
Set-Content -LiteralPath $config -Value $yaml -Encoding ASCII
Write-Host "  wrote $config" -ForegroundColor DarkGray

# ---------- register as an auto-starting task ----------
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
  $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existing) { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
  # $cfExe already resolved above
  $action = New-ScheduledTaskAction -Execute $cfExe -Argument "tunnel --config `"$config`" run $tunnelName"
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Whitty Hybrid permanent Cloudflare tunnel" | Out-Null
  Start-ScheduledTask -TaskName $taskName
  Write-Host "  ✅ installed scheduled task '$taskName' (starts at logon, restarts on failure)" -ForegroundColor Green
} else {
  Write-Host "  ! ScheduledTask cmdlets unavailable - start it manually:" -ForegroundColor Yellow
  Write-Host "      cloudflared tunnel --config `"$config`" run $tunnelName" -ForegroundColor White
}

Write-Host ""
Write-Host "  ==============================================================" -ForegroundColor Green
Write-Host "   Permanent URL - paste into the app:  Connect my PC" -ForegroundColor Green
Write-Host "   https://$Hostname" -ForegroundColor White
Write-Host "  ==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  IMPORTANT: the app only talks to known tunnel hosts. Add yours on Vercel:" -ForegroundColor Yellow
Write-Host "    Project -> Settings -> Environment Variables -> BRIDGE_ALLOWED_HOSTS = $Hostname" -ForegroundColor White
Write-Host "    (comma-separate several; *.ts.net and *.trycloudflare.com are allowed by default)" -ForegroundColor DarkGray
