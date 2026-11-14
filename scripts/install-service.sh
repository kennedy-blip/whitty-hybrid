#!/usr/bin/env bash
# Whitty Hybrid — run the daemon in the background (systemd user service, Linux)
#   bash scripts/install-service.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
DAEMON="$ROOT/daemon"
PY="$DAEMON/.venv/bin/python"

[ -x "$PY" ] || { echo "  ✗ No virtualenv at $DAEMON/.venv — run whitty.sh once first."; exit 1; }
[ -f "$DAEMON/.env" ] || echo "  ! daemon/.env missing — add BRIDGE_TOKEN=... or the daemon starts tokenless."

UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/whitty-daemon.service" <<UNIT
[Unit]
Description=Whitty Hybrid local diagnostics + VPN daemon
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$DAEMON
ExecStart=$PY main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now whitty-daemon.service
sleep 2
systemctl --user --no-pager status whitty-daemon.service | head -n 8 || true
echo ""
echo "  ✅ Installed user service 'whitty-daemon'"
echo "     logs:    journalctl --user -u whitty-daemon -f"
echo "     stop:    systemctl --user stop whitty-daemon"
echo "     remove:  systemctl --user disable --now whitty-daemon && rm $UNIT_DIR/whitty-daemon.service"
echo ""
echo "  To keep it running after logout:  sudo loginctl enable-linger \$USER"
echo "  A tunnel is still a separate process; for a stable URL use a named tunnel or Tailscale."
