"""Port/process mapping + network stack recovery."""
import subprocess, platform, json
import psutil

def list_ports():
    conns = psutil.net_connections(kind="inet")
    out = []
    for c in conns:
        try:
            proc = psutil.Process(c.pid) if c.pid else None
            out.append({
                "protocol": "TCP" if c.type == 4 else "UDP",
                "local": f"{c.laddr.ip}:{c.laddr.port}" if c.laddr else None,
                "remote": f"{c.raddr.ip}:{c.raddr.port}" if c.raddr else None,
                "status": c.status, "pid": c.pid,
                "process": proc.name() if proc else None,
                "path": proc.exe() if proc else None,
            })
        except Exception:
            continue
    # Highlight common dev ports
    dev = [p for p in out if p["local"] and p["local"].split(":")[-1] in ("3000", "3001", "5173", "8000", "8080", "5432", "3306", "6379")]
    return {"total": len(out), "connections": out, "devPorts": dev}

def kill_process(pid: int):
    try:
        p = psutil.Process(pid)
        p.terminate()
        p.wait(timeout=5)
        return {"ok": True, "pid": pid, "name": p.name()}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def network_recovery(action: str):
    """Mutating: flush DNS, renew DHCP, reset Winsock. Requires approval."""
    os_name = platform.system()
    cmds = {
        "flush_dns": {"Windows": ["ipconfig", "/flushdns"], "Darwin": ["dscacheutil", "-flushcache"], "Linux": ["resolvectl", "flush-caches"]},
        "renew_dhcp": {"Windows": ["ipconfig", "/release", "&&", "ipconfig", "/renew"], "Darwin": ["ipconfig", "set", "en0", "DHCP"], "Linux": ["dhclient", "-r", "&&", "dhclient"]},
        "reset_winsock": {"Windows": ["netsh", "winsock", "reset"], "Darwin": [], "Linux": []},
        "reset_tcpip": {"Windows": ["netsh", "int", "ip", "reset"], "Darwin": [], "Linux": []},
    }
    spec = cmds.get(action, {})
    cmd = spec.get(os_name)
    if not cmd:
        return {"ok": False, "error": f"Action '{action}' not supported on {os_name}"}
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return {"ok": r.returncode == 0, "action": action, "output": (r.stdout + r.stderr)[:2000]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def system_overview():
    return {
        "cpuPercent": psutil.cpu_percent(interval=0.5),
        "memoryPercent": psutil.virtual_memory().percent,
        "diskPercent": psutil.disk_usage("/").percent,
        "bootTime": psutil.boot_time(),
        "processes": len(psutil.pids()),
        "interfaces": {k: {"up": v.isup, "speed": v.speed, "mtu": v.mtu} for k, v in psutil.net_if_stats().items()},
        "ipAddresses": {k: [a.address for a in v] for k, v in psutil.net_if_addrs().items()},
    }
