# Whitty Hybrid Daemon (The Hands)

Runs on your PC. Gives the Vercel Brain hands: Wi-Fi scan, ports, power-state, network recovery, WireGuard VPN.

## Quick start
```bash
cd daemon
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
export BRIDGE_TOKEN=your-secret   # must match Vercel env
python main.py
```

## Expose to Vercel (production)
```bash
cloudflared tunnel --url http://localhost:8765
# copy the https://xxx.trycloudflare.com URL into Vercel as BRIDGE_URL
```

## VPN
- One-click: call `POST /execute {"tool":"vpn_connect","approved":true}` — auto-installs WireGuard if missing.
- Mesh: `vpn_init_mesh` with your public endpoint generates server + phone configs.
- Exit node: `vpn_apply_config` with a VPS WireGuard client config.
