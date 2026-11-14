# ⚡ Activate Whitty Hybrid on your PC

**Live app:** https://whitty-hybrid.vercel.app
**Your bridge token:** `b6b8d9818bd3791d4903a7b9e3a723ec`
*(already stored on Vercel — you paste the same value into the daemon)*

> ⚠️ **Clone the right branch.** `git clone` alone gives you `main`, which is still the empty starter.
> Use `-b arena/918f92fd-whitty-hybrid`, or run `git checkout` on the existing clone (Step 0b).

---

## Step 0 — Get the code

**Fresh clone (correct way):**
```bash
git clone -b arena/918f92fd-whitty-hybrid https://github.com/kennedy-blip/whitty-hybrid.git
cd whitty-hybrid
```

**Already cloned and seeing `The argument 'scripts\activate.ps1' ... does not exist`?** You're on `main`. Fix it in place — no re-clone:
```powershell
git fetch origin arena/918f92fd-whitty-hybrid
git checkout arena/918f92fd-whitty-hybrid
```
Then continue with Step 1.

---

## Step 1 — One command

### Windows (PowerShell)
```powershell
$env:BRIDGE_TOKEN="b6b8d9818bd3791d4903a7b9e3a723ec"
powershell -ExecutionPolicy Bypass -File .\scripts\activate.ps1
```
or, shorter, from the repo root:
```powershell
.\whitty.ps1
```

### macOS / Linux
```bash
BRIDGE_TOKEN=b6b8d9818bd3791d4903a7b9e3a723ec bash whitty.sh
```

The script: finds Python (prefers 3.13/3.12 when available) → creates `.venv` (rebuilds it if a different Python made it) → installs `fastapi/uvicorn/psutil/websockets` → starts the daemon on `:8765` → verifies `/health` → opens a Cloudflare tunnel → **prints the URL to paste into the app**.

### Zero-prompt option
Put the token in `daemon/.env` (gitignored) instead of the environment:
```bash
cp daemon/.env.example daemon/.env     # then edit BRIDGE_TOKEN=...
```
The daemon loads that file automatically, so a plain `python daemon/main.py` is enough.

---

## Step 2 — Connect the web app
1. Open https://whitty-hybrid.vercel.app
2. Card **🔗 Connect my PC** → paste the `https://….trycloudflare.com` URL → **Save & Test**
3. Badge turns **● Daemon Online** ✅

No tunnel? Use `http://<your-PC-LAN-IP>:8765` — same Wi-Fi only.

---

## Step 3 — Use it
| Feature | What to click |
|---|---|
| DNS / SSL / CORS / API health | **Tools → Cloud Sentinel** (runs on Vercel) |
| Wi-Fi scan, adapter power, ports, system | **Tools → Local Bridge** |
| Saved Wi-Fi passwords | **Tools → Saved Wi-Fi Passwords** → Approve |
| Sign-in / 802.1X / corporate networks | **Tools → Sign-in / 802.1X Profile** (EAP method, stored identity, PSK) |
| "This Wi-Fi wants me to log in" | **Tools → Captive Portal Check** (returns the portal URL) |
| One-click VPN | **🔐 Connect VPN on My PC** → **Approve** the card |
| Everything that ran | **Audit Trail** (SQLite at `daemon/audit.db`) |

VPN needs an elevated shell (Administrator on Windows, `sudo` on macOS/Linux) because it creates a network tunnel.

**Approvals:** anything that changes your PC returns `requiresApproval` from the daemon and renders an **Approve & Run / Reject** card. The daemon refuses to execute it until your approval arrives — buttons work in both the Tools panel and the AI chat.

**Wi-Fi passwords:** Windows needs the daemon running **as Administrator** for `netsh wlan show profile … key=clear`; macOS may ask for Keychain access; Linux needs `sudo` to read `/etc/NetworkManager/system-connections`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `The argument 'scripts\activate.ps1' ... does not exist` | You cloned `main`. Do a `git checkout arena/918f92fd-whitty-hybrid` (Step 0) |
| `python` not recognised | Install Python 3 from python.org and tick **Add python.exe to PATH**, then reopen PowerShell |
| `running scripts is disabled on this system` | You dropped `-ExecutionPolicy Bypass`, or run `Unblock-File .\scripts\activate.ps1` |
| `○ Daemon Offline` in the app | Daemon stopped, or the quick-tunnel URL changed — re-run and re-paste |
| `401 Invalid bridge token` | Daemon token ≠ Vercel token. Use exactly `b6b8d9818bd3791d4903a7b9e3a723ec` and restart |
| Tunnel URL printed but Save & Test fails | Only `trycloudflare.com`, `ngrok`, `*.ts.net` and localhost are allowed — re-copy the full `https://` URL |
| `pip install` fails behind a firewall | `set HTTPS_PROXY=http://host:port` then rerun |
| `Building wheel for pydantic-core ... error: interpreter version (3.14) is newer than PyO3's maximum supported version (3.13)` | Fixed in the repo — `git pull` and rerun. Cause: old hard pins had no 3.14 wheel so pip compiled from Rust. If it still happens, use Python 3.12/3.13: `py -3.12 -m venv .venv` then `.\daemon\.venv\Scripts\python.exe -m pip install -r daemon\requirements.txt` |
| Any "failed building wheel" / maturin / cargo error | Your Python is newer than the published wheels. Install 3.12 or 3.13 and/or set `$env:WHITTY_PYTHON="C:\Python312\python.exe"` |
| `.venv` created by a different Python | The launcher now detects this and rebuilds it automatically |
| VPN: "WireGuard not installed" | The daemon auto-installs it; if that fails install from wireguard.com and retry |
| VPN connect hangs / no public IP | Restart the shell as Administrator / `sudo` |

---

## Keep the daemon running without a terminal

Close the terminal and the daemon dies with it. Install it as a background service instead:

**Windows** (Scheduled Task, no console window, starts at logon, runs elevated so WireGuard + `netsh key=clear` work):
```powershell
notepad .\daemon\.env      # one line:  BRIDGE_TOKEN=b6b8d9818bd3791d4903a7b9e3a723ec
.\scripts\install-service.ps1 -StartNow
```
Manage: `Start-ScheduledTask -TaskName WhittyHybridDaemon` / `Stop-ScheduledTask …` / `Unregister-ScheduledTask …`

**Linux** (systemd user service):
```bash
bash scripts/install-service.sh
journalctl --user -u whitty-daemon -f
```

> The **tunnel** is still its own process with a URL that changes on every restart. For an always-on URL use a free *named* Cloudflare tunnel (`cloudflared tunnel create witty` + DNS route) or Tailscale (`tailscale funnel 8765`) — `*.trycloudflare.com` quick tunnels are temporary by design.

## Optional — your own VPN exit node (VPS)
```bash
scp scripts/deploy-vps.sh root@YOUR_VPS:/root/
ssh root@YOUR_VPS "bash /root/deploy-vps.sh"
```
Then in the VPN panel enter `YOUR_VPS_IP:51820` → **Generate** → **Apply to My PC**.
