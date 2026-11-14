# ⚡ Whitty Hybrid — Diagnostic Agent

Dual-environment AI sysadmin: **Vercel Brain** (cloud diagnostics + AI chat) × **Python Daemon Hands** (your PC) + **one-click WireGuard VPN**.

## Architecture
```
[Vercel: Next.js + AI SDK] ──HTTPS──> [Daemon on your PC :8765]
   Cloud Sentinel tools                Wi-Fi / ports / power / recovery
   AI chat (maxSteps chaining)         WireGuard VPN manager
   VPN panel + approval cards          SQLite audit trail
```

**Live app:** https://whitty-hybrid.vercel.app — see **[ACTIVATE.md](ACTIVATE.md)** for full PC activation steps.

**One-command PC setup:** `bash whitty.sh` (macOS/Linux) · `.\whitty.ps1` (Windows). Put `BRIDGE_TOKEN=...` in `daemon/.env` to skip prompts.

## Quick start
### 1. Brain (Vercel / local)
```bash
npm install
cp .env.example .env.local   # set OPENAI_API_KEY, BRIDGE_URL, BRIDGE_TOKEN
npm run dev                  # http://localhost:3000
```
Deploy: push to GitHub → import in Vercel → set env vars. Works in demo mode without an AI key (panels still work).

The cloud app takes the daemon URL at runtime via the **🔗 Connect my PC** card (stored in your browser), so a fresh Cloudflare Tunnel URL needs no redeploy. Only Cloudflare Tunnel / ngrok / Tailscale / localhost hosts are accepted as bridge targets.

### 2. Hands (your PC)
```bash
git clone -b arena/918f92fd-whitty-hybrid https://github.com/kennedy-blip/whitty-hybrid.git
cd whitty-hybrid
bash whitty.sh          # Windows: .\whitty.ps1
```
That creates the venv, installs deps, starts the daemon on `:8765` and opens a Cloudflare tunnel.

Manual equivalent:
```bash
cd daemon
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env    # then set BRIDGE_TOKEN=...
python main.py
```
Then paste the tunnel URL into the app's **🔗 Connect my PC** card (or set `BRIDGE_URL` on Vercel).

## Features
- **Cloud Sentinel:** DNS trace, SSL audit, CORS/header analysis, API latency triage.
- **Local Bridge:** full Wi-Fi decrypt (SSID/BSSID/RSSI/channel/congestion), adapter power-state + fix, port→PID mapping, DNS/DHCP/Winsock recovery.
- **Safety:** read-only auto-approved; mutating actions show Approve/Reject cards; every action logged to SQLite (`daemon/audit.db`).
- **VPN:** one-click WireGuard — daemon auto-installs `wireguard-tools`, brings the tunnel up on your PC, verifies public IP. Generate phone/laptop configs + QR codes. Optional VPS exit-node via `scripts/deploy-vps.sh`.

## Env vars
| Var | Purpose |
|---|---|
| `OPENAI_API_KEY` | AI agent (demo mode if unset) |
| `BRIDGE_URL` | Daemon URL (localhost or Cloudflare Tunnel) |
| `BRIDGE_TOKEN` | Shared secret for the bridge |
