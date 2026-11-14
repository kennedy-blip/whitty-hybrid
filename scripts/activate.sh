#!/usr/bin/env bash
# Whitty Hybrid — one-command activation for macOS / Linux
#   bash whitty.sh
# Token comes from $BRIDGE_TOKEN, daemon/.env, or a prompt.
# Force an interpreter with:  WHITTY_PYTHON=/usr/local/bin/python3.12 bash whitty.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
echo ""
echo "  Whitty Hybrid — activating local Hands"
echo "  repo: $ROOT"

ver() { "$1" -c "import sys;print('%d.%d' % sys.version_info[:2])" 2>/dev/null || true; }

# ---------- preflight: is this checkout current? ----------
if command -v git >/dev/null 2>&1; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -n "${BRANCH:-}" ] && [ "$BRANCH" != "main" ]; then
    echo "  ! You are on branch '$BRANCH'. 'main' carries the newest daemon code."
    echo "    Switch with:  git checkout main && git pull"
  fi
fi
if [ -f daemon/requirements.txt ] && grep -Eq '^[[:space:]]*pydantic==2\.(9|1[01])' daemon/requirements.txt; then
  echo ""
  echo "  ✗ This checkout still has the OLD pinned requirements (pydantic==2.9.x)." >&2
  echo "    No wheel exists for newer Pythons, so pip compiles Rust and fails." >&2
  echo "    Fix — update the code, then rerun:" >&2
  echo "        git checkout main && git pull && bash whitty.sh" >&2
  exit 1
fi

# ---------- pick a Python ----------
PY=""
if [ -n "${WHITTY_PYTHON:-}" ] && [ -x "${WHITTY_PYTHON}" ]; then
  PY="$WHITTY_PYTHON"
fi
if [ -z "$PY" ]; then
  # Prefer a well-supported interpreter: brand-new CPython releases are the
  # usual cause of "no wheel published, must build from source".
  for cand in python3.13 python3.12 python3.11 python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then PY=$(command -v "$cand"); break; fi
  done
fi
if [ -z "$PY" ]; then
  echo "  ✗ Python 3 not found. Install 3.12 or 3.13 (python.org or your package manager)." >&2
  exit 1
fi
PYVER=$(ver "$PY")
echo "  python: $PY ($PYVER)"

# ---------- token ----------
if [ -z "${BRIDGE_TOKEN:-}" ] && [ -f daemon/.env ]; then
  BRIDGE_TOKEN=$(grep -Eo '^\s*BRIDGE_TOKEN\s*=\s*.*' daemon/.env | head -n1 | cut -d= -f2- | tr -d '"'"'"' \r' || true)
fi
if [ -z "${BRIDGE_TOKEN:-}" ]; then
  if [ -t 0 ]; then
    read -r -p "  Paste your BRIDGE_TOKEN (Vercel → Settings → Environment Variables): " BRIDGE_TOKEN || true
  else
    echo "  ! No BRIDGE_TOKEN and no terminal to prompt on — starting tokenless (the app will get 401s)."
  fi
fi
export BRIDGE_TOKEN

# ---------- venv (repaired if damaged, rebuilt if from another Python) ----------
cd daemon
if [ -d .venv ] && { [ ! -f .venv/pyvenv.cfg ] || [ ! -x .venv/bin/python ]; }; then
  echo "  .venv is damaged (no pyvenv.cfg or python) — repairing"
  "$PY" -m venv --clear .venv || {
    rm -rf .venv 2>/dev/null || true
    if [ -d .venv ]; then
      echo "  could not remove .venv (files locked by a running daemon) — using .venv2"
      "$PY" -m venv .venv2 && mv -f .venv2 .venv 2>/dev/null || true
    else
      "$PY" -m venv .venv
    fi
  }
fi
if [ -d .venv ] && [ -f .venv/pyvenv.cfg ]; then
  EXISTING=$(grep -Eo 'version(_info)? *= *"?[0-9]+\.[0-9]+' .venv/pyvenv.cfg | grep -Eo '[0-9]+\.[0-9]+' | head -n1 || true)
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "$PYVER" ]; then
    echo "  existing .venv uses Python $EXISTING — rebuilding for $PYVER"
    rm -rf .venv
  fi
fi
[ -d .venv ] || { echo "  creating virtualenv ..."; "$PY" -m venv .venv; }
# shellcheck disable=SC1091
source .venv/bin/activate

# ---------- dependencies ----------
echo "  installing dependencies (first run ~30s) ..."
python -m pip install --quiet --disable-pip-version-check --upgrade pip || true
if ! python -m pip install --disable-pip-version-check --prefer-binary -r requirements.txt; then
  echo ""
  echo "  ✗ Dependency install failed." >&2
  echo "    If you saw a Rust/maturin build, your Python is newer than the published wheels." >&2
  echo "    Install 3.12/3.13 and retry, e.g.:  WHITTY_PYTHON=\$(command -v python3.12) bash whitty.sh" >&2
  echo "    Behind a proxy?  export HTTPS_PROXY=http://host:port" >&2
  exit 1
fi
echo "  dependencies OK"

# ---------- daemon ----------
DAEMON_PID=""
if curl -fsS --max-time 3 http://localhost:8765/health >/dev/null 2>&1; then
  echo "  a daemon is already answering on :8765 — leaving it alone"
  echo "    (stop it first if you want this script to manage it)"
else
  echo "  starting daemon on :8765 ..."
  python main.py &
  DAEMON_PID=$!
  sleep 3
  if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "  ✗ daemon exited immediately — port already in use, or run 'python main.py' in daemon/ to see why" >&2
    exit 1
  fi
  if curl -fsS --max-time 5 http://localhost:8765/health >/dev/null 2>&1; then
    echo "  daemon is healthy"
  fi
fi

# ---------- tunnel ----------
if ! command -v cloudflared >/dev/null 2>&1; then
  echo ""
  echo "  cloudflared not installed. Either:"
  echo "    a) brew install cloudflared   (Linux: see Cloudflare's download page), then rerun"
  echo "    b) same Wi-Fi only: use  http://<this-Mac-or-Linux-LAN-IP>:8765  in the web app"
  echo ""
  echo "  Daemon running. Ctrl+C to stop."
  if [ -n "${DAEMON_PID:-}" ]; then
    trap 'kill $DAEMON_PID 2>/dev/null || true' EXIT INT TERM
    wait $DAEMON_PID
  else
    while true; do sleep 3600; done
  fi
  exit 0
fi

echo "  opening public tunnel ..."
LOG=$(mktemp -t whitty-tunnel)
cloudflared tunnel --url http://localhost:8765 2>"$LOG" &
TUNNEL_PID=$!
trap 'kill ${DAEMON_PID:-} $TUNNEL_PID 2>/dev/null || true' EXIT INT TERM

URL=""
for _ in $(seq 1 30); do
  URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -n1 || true)
  [ -n "$URL" ] && break
  sleep 1
done
echo ""
if [ -n "$URL" ]; then
  echo "  =============================================================="
  echo "   Paste this into the app:  Connect my PC  →  Save & Test"
  echo "   $URL"
  echo "   https://whitty-hybrid.vercel.app"
  echo "  =============================================================="
  echo "   (the URL changes on every restart — just re-paste it)"
else
  echo "  ! tunnel URL not found yet — check $LOG"
fi
echo ""
echo "  Running. Ctrl+C to stop daemon + tunnel."
if [ -n "${DAEMON_PID:-}" ]; then wait $DAEMON_PID; else while true; do sleep 3600; done; fi
