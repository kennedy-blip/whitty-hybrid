"""
Whitty Hybrid — Local Python Daemon (The Hands)
Runs on YOUR PC. Exposes local diagnostics + VPN to the Vercel Brain.

Run:  python main.py          (serves on 0.0.0.0:8765)
Prod: expose with Cloudflare Tunnel:  cloudflared tunnel --url http://localhost:8765
      then set BRIDGE_URL=https://<tunnel-host> on Vercel.
"""
import os, json, time
from pathlib import Path

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

TOKEN = os.environ.get("BRIDGE_TOKEN", "")

def _auth(authorization: str | None):
    if TOKEN and authorization != f"Bearer {TOKEN}":
        raise HTTPException(401, "Invalid bridge token")

READ_ONLY = {"scan_wifi", "adapter_power_status", "list_ports", "system_overview", "vpn_status", "audit_recent"}
MUTATING = {"disable_adapter_sleep", "kill_process", "network_recovery", "vpn_connect", "vpn_disconnect", "vpn_kill_switch", "vpn_init_mesh", "vpn_apply_config"}

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
def health(): return {"ok": True}

if __name__ == "__main__":
    print("Whitty Hybrid Daemon starting on :8765 ...")
    print("Set BRIDGE_TOKEN env to match Vercel. Expose via: cloudflared tunnel --url http://localhost:8765")
    uvicorn.run(app, host="0.0.0.0", port=8765)
