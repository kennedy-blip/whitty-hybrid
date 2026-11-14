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

if ($Uninstall) {
  if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
  }
  if (Have "tailscale") { & tailscale funnel reset 2>$null | Out-Null }
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
  & tailscale up
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  ! 'tailscale up' returned $LASTEXITCODE - finish the login, then rerun." -ForegroundColor Yellow
    exit 1
  }

  Write-Host "  enabling Funnel (public HTTPS on your tailnet, no domain needed) ..." -ForegroundColor Yellow
  & tailscale funnel --bg $Port
  Start-Sleep -Seconds 3
  $status = (& tailscale funnel status 2>$null | Out-String)
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
if (-not (Have "cloudflared")) {
  Write-Host "  cloudflared not found." -ForegroundColor Yellow
  if (Have "winget") {
    Write-Host "  Installing: winget install --id Cloudflare.cloudflared -e" -ForegroundColor Yellow
    winget install --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements
    Write-Host "  CLOSE and REOPEN this terminal, then rerun this script." -ForegroundColor Yellow
  } else {
    Write-Host "  Download cloudflared-windows-amd64.exe from Cloudflare's releases page and put it on PATH." -ForegroundColor Yellow
  }
  exit 1
}

$cfDir = Join-Path $env:USERPROFILE ".cloudflared"
$cert = Join-Path $cfDir "cert.pem"
$config = Join-Path $cfDir "config.yml"
$tunnelName = "whitty"

if (-not (Test-Path -LiteralPath $cert)) {
  Write-Host "  First-time login: a browser window opens. Pick the domain you want to use." -ForegroundColor Yellow
  & cloudflared tunnel login
  if (-not (Test-Path -LiteralPath $cert)) {
    Write-Host "  X Login did not complete (no cert.pem). Rerun when you can finish the browser step." -ForegroundColor Red
    Write-Host "    A Cloudflare account with a domain is required for named tunnels." -ForegroundColor Yellow
    Write-Host "    No domain? Use Tailscale instead:  .\scripts\install-tunnel.ps1 -Mode tailscale" -ForegroundColor Yellow
    exit 1
  }
}

# create (or reuse) the tunnel
$list = (& cloudflared tunnel list 2>$null | Out-String)
$tunnelId = ""
if ($list -match "(?m)^\S+\s+$tunnelName\s") {
  $tunnelId = ([regex]::Match($list, "(?m)^(\S+)\s+$tunnelName\s")).Groups[1].Value
  Write-Host "  reusing existing tunnel '$tunnelName' ($tunnelId)" -ForegroundColor DarkGray
} else {
  & cloudflared tunnel create $tunnelName
  $list = (& cloudflared tunnel list 2>$null | Out-String)
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
& cloudflared tunnel route dns $tunnelName $Hostname

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
  $cfExe = (Get-Command cloudflared).Source
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
