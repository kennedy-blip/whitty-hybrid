"""
Whitty Hybrid — Local Python Daemon (The Hands)
Runs on YOUR PC. Exposes local diagnostics + VPN to the Vercel Brain.

Run:  python main.py          (serves on 0.0.0.0:8765)
Prod: expose with Cloudflare Tunnel:  cloudflared tunnel --url http://localhost:8765
      then set BRIDGE_URL=https://<tunnel-host> on Vercel.
"""
import os, sys, json, time, hmac
from pathlib import Path

# ---------------------------------------------------------------------------
# A Scheduled Task launches pythonw.exe, which has NO console: sys.stdout and
# sys.stderr are None. uvicorn's logging writes to them at startup, so the
# process used to die silently with no trace anywhere (Task Scheduler showed
# 0x1 and nothing else). Point both at daemon.log instead - a background
# daemon that cannot explain itself is not debuggable.
# ---------------------------------------------------------------------------
def _init_headless_logging():
    log_path = Path(__file__).with_name("daemon.log")
    if sys.stdout is not None and sys.stderr is not None:
        return log_path
    try:
        if log_path.exists() and log_path.stat().st_size > 2_000_000:
            log_path.replace(log_path.with_name("daemon.log.old"))
    except Exception:
        pass
    try:
        fh = open(log_path, "a", encoding="utf-8", errors="replace", buffering=1)
    except Exception:
        return log_path
    if sys.stdout is None:
        sys.stdout = fh
    if sys.stderr is None:
        sys.stderr = fh
    return log_path


LOG_PATH = _init_headless_logging()


def _excepthook(exc_type, exc, tb):
    import traceback
    try:
        sys.stderr.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] unhandled exception\n")
        traceback.print_exception(exc_type, exc, tb, file=sys.stderr)
        sys.stderr.flush()
    except Exception:
        pass


sys.excepthook = _excepthook

# Load daemon/.env (simple KEY=VALUE) so you don't have to export vars every time.
_env = Path(__file__).with_name(".env")
if _env.exists():
    for _line in _env.read_text(encoding="utf-8").splitlines():
        _line = _line.strip()
        if not _line or _line.startswith("#") or "=" not in _line:
            continue
        _k, _v = _line.split("=", 1)
        os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

import wifi_scanner, network_tools, vpn_manager
from audit_log import log, recent

app = FastAPI(title="Whitty Hybrid Daemon", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

TOKEN = os.environ.get("BRIDGE_TOKEN", "").strip()
HOST = os.environ.get("BRIDGE_HOST", "127.0.0.1").strip() or "127.0.0.1"

if not TOKEN:
    print("")
    print("  ============================================================")
    print("   REFUSING TO START: no BRIDGE_TOKEN")
    print("  ============================================================")
    print("  Without a token this daemon accepts ANY caller - and it can")
    print("  reveal saved Wi-Fi passwords and kill processes. A tunnel")
    print("  would expose that to the whole internet.")
    print("")
    print("  Create daemon/.env with one line:")
    print("      BRIDGE_TOKEN=<same value as the Vercel env var>")
    print("  or set it for this shell:")
    print("      $env:BRIDGE_TOKEN=\"...\"")
    print("")
    raise SystemExit(2)


def _auth(authorization: str | None):
    # Fail closed: a missing/!valid token is always rejected.
    provided = (authorization or "").removeprefix("Bearer ").strip()
    if not hmac.compare_digest(provided, TOKEN):
        raise HTTPException(401, "Invalid bridge token")

READ_ONLY = {"scan_wifi", "adapter_power_status", "list_ports", "system_overview", "vpn_status", "audit_recent", "captive_portal_status"}
MUTATING = {"disable_adapter_sleep", "wifi_saved_passwords", "wifi_profile_details", "kill_process", "network_recovery", "vpn_connect", "vpn_disconnect", "vpn_kill_switch", "vpn_init_mesh", "vpn_apply_config"}

@app.get("/status")
def status(authorization: str | None = Header(None)):
    _auth(authorization)
    return {"ok": True, "daemon": "online", "ts": time.time(), "vpn": vpn_manager.status()}

@app.get("/audit")
def audit(authorization: str | None = Header(None)):
    _auth(authorization)
    return {"entries": recent(100)}

@app.post("/execute")
async def execute(req: Request, authorization: str | None = Header(None)):
    _auth(authorization)
    body = await req.json()
    tool, args = body.get("tool"), body.get("args", {})
    approved = body.get("approved")
    if tool in MUTATING and approved is not True:
        log(tool, args, {"blocked": "requires_approval"}, approved=False, source="daemon-gate")
        return {"ok": False, "requiresApproval": True, "tool": tool,
                "message": f"'{tool}' is mutating and needs human approval. Re-send with approved=true."}
    try:
        if tool == "scan_wifi": result = wifi_scanner.scan_wifi()
        elif tool == "wifi_saved_passwords": result = wifi_scanner.saved_passwords()
        elif tool == "wifi_profile_details": result = wifi_scanner.wifi_profile_details(args.get("ssid") or None)
        elif tool == "captive_portal_status": result = wifi_scanner.captive_portal_status()
        elif tool == "adapter_power_status": result = wifi_scanner.adapter_power_status()
        elif tool == "disable_adapter_sleep": result = wifi_scanner.disable_adapter_sleep()
        elif tool == "list_ports": result = network_tools.list_ports()
        elif tool == "kill_process": result = network_tools.kill_process(int(args.get("pid")))
        elif tool == "network_recovery": result = network_tools.network_recovery(args.get("action", "flush_dns"))
        elif tool == "system_overview": result = network_tools.system_overview()
        elif tool == "vpn_status": result = vpn_manager.status()
        elif tool == "vpn_connect": result = vpn_manager.connect()
        elif tool == "vpn_disconnect": result = vpn_manager.disconnect()
        elif tool == "vpn_kill_switch": result = vpn_manager.kill_switch(bool(args.get("enable")))
        elif tool == "vpn_init_mesh": result = vpn_manager.init_mesh(args.get("endpoint", ""), args.get("clientName", "phone"))
        elif tool == "vpn_apply_config": result = vpn_manager.apply_client_config(args.get("config", ""))
        elif tool == "audit_recent": result = {"entries": recent(int(args.get("limit", 50)))}
        else: return {"ok": False, "error": f"Unknown tool: {tool}"}
        log(tool, args, result, approved=approved, source="daemon")
        return {"ok": True, "tool": tool, "result": result}
    except Exception as e:
        log(tool, args, {"error": str(e)}, approved=approved, source="daemon")
        return {"ok": False, "tool": tool, "error": str(e)}

@app.get("/health")
def health(): return {"ok": True, "auth": "token", "bind": HOST}

def _port_free(host: str, port: int) -> bool:
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sk:
        sk.settimeout(0.5)
        return sk.connect_ex((host if host != "0.0.0.0" else "127.0.0.1", port)) != 0


def _selftest():
    """python main.py --selftest - explains why the background daemon won't run."""
    print(f"python        : {sys.version.split()[0]}")
    print(f"token         : {'set (' + str(len(TOKEN)) + ' chars)' if TOKEN else 'MISSING -> daemon refuses to start'}")
    print(f".env present  : {Path(__file__).with_name('.env').exists()}")
    print(f"bind          : {HOST}:8765")
    print(f"port free     : {_port_free(HOST, 8765)}" + ("" if _port_free(HOST, 8765) else "  <- something already listens here"))
    print(f"log file      : {LOG_PATH}")
    for mod in ("wifi_scanner", "network_tools", "vpn_manager", "audit_log"):
        try:
            __import__(mod)
            print(f"import {mod:<14}: ok")
        except Exception as exc:
            print(f"import {mod:<14}: FAILED - {exc}")
    return 0 if TOKEN else 2


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        raise SystemExit(_selftest())
    started = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n[{started}] Whitty Hybrid Daemon starting on {HOST}:8765")
    print(f"[{started}] token loaded ({len(TOKEN)} chars), .env={Path(__file__).with_name('.env').exists()}")
    print(f"[{started}] expose with: tailscale funnel --bg 8765  (or cloudflared tunnel --url http://localhost:8765)")
    try:
        uvicorn.run(app, host=HOST, port=8765)
    except Exception as exc:
        import traceback
        traceback.print_exc(file=sys.stderr)
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] FATAL: {exc}")
        raise SystemExit(1)
