#!/usr/bin/env bash
# Whitty Hybrid — one-command activation for macOS / Linux
# Usage: BRIDGE_TOKEN=xxxx bash scripts/activate.sh
set -e
cd "$(dirname "$0")/.."
echo "⚡ Whitty Hybrid — activating local Hands"

PY=$(command -v python3 || command -v python)
[ -z "$PY" ] && { echo "❌ Python 3 not found. Install from python.org"; exit 1; }

cd daemon
[ -d .venv ] || "$PY" -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -q -r requirements.txt

if [ -z "$BRIDGE_TOKEN" ]; then
  read -r -p "Paste your BRIDGE_TOKEN (Vercel → Settings → Environment Variables): " BRIDGE_TOKEN
fi
export BRIDGE_TOKEN

echo "▶ starting daemon on :8765 ..."
python main.py &
DAEMON_PID=$!
sleep 3

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared not found — printing local-only instructions."
  echo "Install: brew install cloudflared   (Linux: see developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)"
else
  echo "▶ opening public tunnel ..."
  cloudflared tunnel --url http://localhost:8765 2>&1 | tee /tmp/whitty-tunnel.log &
  TUNNEL_PID=$!
  sleep 8
  URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/whitty-tunnel.log | head -n1)
  echo ""
  echo "=============================================================="
  echo "✅ Paste this into the web app → 'Connect my PC' → Save & Test:"
  echo "   $URL"
  echo "=============================================================="
  trap 'kill $DAEMON_PID $TUNNEL_PID 2>/dev/null' EXIT
fi
wait $DAEMON_PID
