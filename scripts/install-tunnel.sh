#!/usr/bin/env bash
# Whitty Hybrid - permanent tunnel (Linux / macOS)
#   bash scripts/install-tunnel.sh                    # auto-detect
#   bash scripts/install-tunnel.sh --mode tailscale
#   bash scripts/install-tunnel.sh --mode cloudflare --hostname witty.example.com
set -euo pipefail
MODE="auto"; HOSTNAME_ARG=""; PORT=8765
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --hostname) HOSTNAME_ARG="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
echo ""
echo "  Whitty Hybrid — permanent tunnel"

have() { command -v "$1" >/dev/null 2>&1; }

if [ "$MODE" = "auto" ]; then
  if have tailscale; then MODE=tailscale; elif have cloudflared; then MODE=cloudflare; else MODE=tailscale; fi
fi
echo "  mode: $MODE"

if [ "$MODE" = "tailscale" ]; then
  have tailscale || { echo "  ✗ Install Tailscale (https://tailscale.com/download) then rerun." >&2; exit 1; }
  echo "  tailscale up (login may be required) ..."
  tailscale up || { echo "  ! finish login, then rerun" >&2; exit 1; }
  echo "  enabling Funnel on port $PORT ..."
  tailscale funnel --bg "$PORT"
  sleep 2
  STATUS=$(tailscale funnel status 2>/dev/null || true)
  echo "$STATUS"
  URL=$(printf '%s' "$STATUS" | grep -Eo 'https://[a-z0-9.-]+\.ts\.net' | head -n1 || true)
  echo ""
  if [ -n "$URL" ]; then
    echo "  =============================================================="
    echo "   Permanent URL — paste into the app: Connect my PC"
    echo "   $URL"
    echo "  =============================================================="
  else
    echo "  ! Could not read the URL. Run 'tailscale funnel status' manually."
    echo "    Funnel may need enabling for your tailnet (nodeAttrs funnel)."
  fi
  echo "  Tailscale runs as a system service — survives reboot. Stop: tailscale funnel reset"
  exit 0
fi

have cloudflared || { echo "  ✗ Install cloudflared then rerun." >&2; exit 1; }
CF_DIR="$HOME/.cloudflared"
mkdir -p "$CF_DIR"
[ -f "$CF_DIR/cert.pem" ] || { echo "  cloudflared tunnel login (browser) ..."; cloudflared tunnel login; }
[ -f "$CF_DIR/cert.pem" ] || { echo "  ✗ login incomplete (no cert.pem). No domain? use --mode tailscale" >&2; exit 1; }

NAME=whitty
ID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$NAME" '$2==n {print $1; exit}')
if [ -z "$ID" ]; then
  cloudflared tunnel create "$NAME" || true
  ID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$NAME" '$2==n {print $1; exit}')
fi
[ -n "$ID" ] || { echo "  ✗ tunnel creation failed — run 'cloudflared tunnel create witty' to see why" >&2; exit 1; }

if [ -z "$HOSTNAME_ARG" ]; then
  echo "  Tunnel '$NAME' ready but no hostname set. Rerun with:"
  echo "      bash scripts/install-tunnel.sh --mode cloudflare --hostname witty.mydomain.com"
  exit 1
fi

cloudflared tunnel route dns "$NAME" "$HOSTNAME_ARG"
cat > "$CF_DIR/config.yml" <<YAML
tunnel: $ID
credentials-file: $CF_DIR/$ID.json

ingress:
  - hostname: $HOSTNAME_ARG
    service: http://localhost:$PORT
  - service: http_status:404
YAML

UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/whitty-tunnel.service" <<UNIT
[Unit]
Description=Whitty Hybrid permanent Cloudflare tunnel
After=network-online.target whitty-daemon.service

[Service]
Type=simple
ExecStart=$(command -v cloudflared) tunnel --config $CF_DIR/config.yml run $NAME
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now whitty-tunnel.service
echo ""
echo "  =============================================================="
echo "   Permanent URL — paste into the app: Connect my PC"
echo "   https://$HOSTNAME_ARG"
echo "  =============================================================="
echo ""
echo "  Add to Vercel env: BRIDGE_ALLOWED_HOSTS=$HOSTNAME_ARG"
