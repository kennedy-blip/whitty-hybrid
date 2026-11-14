# ⚡ Activate Whitty Hybrid on your PC

**Live app:** https://whitty-hybrid.vercel.app
**Your bridge token:** `b6b8d9818bd3791d4903a7b9e3a723ec` *(already set on Vercel — you paste the same value into the daemon)*
**WireGuard:** the daemon auto-installs it when you click Connect VPN.

---

## Step 1 — Get the code onto your PC
```bash
git clone https://github.com/kennedy-blip/whitty-hybrid.git
cd whitty-hybrid
```
(or just download the `daemon/` folder — that's all the local side needs)

## Step 2 — Start the daemon

### Windows (PowerShell)
```powershell
$env:BRIDGE_TOKEN="b6b8d9818bd3791d4903a7b9e3a723ec"
powershell -ExecutionPolicy Bypass -File scripts\activate.ps1
```

### macOS / Linux
```bash
BRIDGE_TOKEN=b6b8d9818bd3791d4903a7b9e3a723ec bash scripts/activate.sh
```

The script creates a virtualenv, installs dependencies, starts the daemon on `:8765`, and (if `cloudflared` is installed) opens a public tunnel and prints the URL.

### Manual, if you prefer
```bash
cd daemon
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
export BRIDGE_TOKEN=b6b8d9818bd3791d4903a7b9e3a723ec
python main.py
```

## Step 3 — Expose it to the cloud (pick one)

**A. Cloudflare Tunnel — recommended, works from anywhere, free**
```bash
# macOS: brew install cloudflared   |  Windows: winget install Cloudflare.cloudflared
cloudflared tunnel --url http://localhost:8765
```
Copy the `https://<random>.trycloudflare.com` URL it prints. The URL changes every restart — that's fine, you just re-paste it.

**B. Same Wi-Fi only** — skip the tunnel and use `http://<your-pc-lan-ip>:8765` (e.g. `http://192.168.1.20:8765`). Find it with `ipconfig` (Windows) or `ifconfig` (macOS/Linux).

## Step 4 — Connect the web app
1. Open https://whitty-hybrid.vercel.app
2. In the **🔗 Connect my PC** card, paste your tunnel URL → **Save & Test**
3. The header badge turns **● Daemon Online** — you're live.

## Step 5 — Use it
- **Cloud Sentinel** — DNS / SSL / CORS / API health, runs on Vercel, no PC needed.
- **Tools tab → Local Bridge** — Wi-Fi scan, adapter power, ports, system overview.
- **🔐 One-Click VPN** — click **⚡ Connect VPN on My PC**; approve when the card appears. First run auto-installs WireGuard, then the tunnel comes up and your public IP changes. Generate a `.conf` / QR for your phone too.
- **Audit Trail** — every command, output and approval, stored in `daemon/audit.db`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `○ Daemon Offline` | Daemon not running, or tunnel URL changed — re-run the tunnel and re-paste the URL |
| `401 Invalid bridge token` | The daemon's `BRIDGE_TOKEN` doesn't match Vercel's. Set the exact value above and restart |
| Cloud tools fail | Those run on Vercel; check the domain/URL is public |
| VPN: "WireGuard not installed" | Let Connect auto-install it, or install manually from wireguard.com and retry |
| VPN connect hangs | Windows/macOS need admin/root for tunnel creation — run the terminal as Administrator / `sudo` |
| `cloudflared` not found | Install it, or use LAN mode (`http://<lan-ip>:8765`) |

## Optional — your own VPN exit node
To route traffic through your own VPS instead of the local hub:
```bash
scp scripts/deploy-vps.sh root@YOUR_VPS:/root/ && ssh root@YOUR_VPS "bash /root/deploy-vps.sh"
```
Then in the VPN panel, enter `YOUR_VPS_IP:51820` as the endpoint and **Generate** → **Apply to My PC**.
