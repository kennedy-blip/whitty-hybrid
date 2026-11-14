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

### Keep it running
`scripts/install-service.ps1` (Windows Scheduled Task) or `scripts/install-service.sh` (systemd user unit) runs the daemon in the background at logon — no terminal required.

`scripts/install-tunnel.ps1` / `.sh` gives the tunnel the same treatment: **`-Mode tailscale`** (stable `https://<pc>.<tailnet>.ts.net`, no domain) or **`-Mode cloudflare -Hostname witty.yourdomain.com`** (named tunnel + scheduled task). No more re-pasting URLs after a reboot.

### Python version note
The daemon needs **Python 3.9+**; **3.12 or 3.13 is recommended**. Dependencies are ranged rather than pinned so pip always downloads a prebuilt wheel — brand-new interpreters (e.g. 3.14) may lack wheels and trigger a Rust source build. Override the interpreter with `WHITTY_PYTHON=/path/to/python3.12` (or `$env:WHITTY_PYTHON` on Windows).

## Features
- **Cloud Sentinel:** DNS trace, SSL audit, CORS/header analysis, API latency triage.
- **Local Bridge:** full Wi-Fi scan (SSID/BSSID/RSSI/channel/congestion), **saved Wi-Fi passwords** (`netsh … key=clear` / macOS Keychain / NetworkManager), adapter power-state + fix, port→PID mapping, DNS/DHCP/Winsock recovery.
- **Safety:** read-only auto-approved; mutating actions (VPN, network reset, kill process, revealing Wi-Fi passwords) show Approve/Reject cards — the daemon refuses them until `approved: true`; every action logged to SQLite (`daemon/audit.db`).
- **VPN:** one-click WireGuard — daemon auto-installs `wireguard-tools`, brings the tunnel up on your PC, verifies public IP. Generate phone/laptop configs + QR codes. Optional VPS exit-node via `scripts/deploy-vps.sh`.

## Env vars
| Var | Purpose |
|---|---|
| `GROQ_API_KEY` | **Preferred** — Groq (OpenAI-compatible) powers the agent |
| `GROQ_MODEL` | Groq model, default `llama-3.3-70b-versatile` |
| `OPENAI_API_KEY` | Fallback provider if no Groq key (demo mode if neither set) |
| `BRIDGE_URL` | Daemon URL (localhost or Cloudflare Tunnel) |
| `BRIDGE_TOKEN` | Shared secret for the bridge |
| `BRIDGE_ALLOWED_HOSTS` | Extra hostnames the app may use as a bridge (named tunnels on your own domain) |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Persistent cloud audit trail (`whitty_audit` table); without them it is per-instance memory |
