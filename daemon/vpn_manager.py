"""
WireGuard VPN Manager — the one-click VPN for the connected PC.

Two modes:
  1. MESH (default): this PC becomes a WireGuard hub. The daemon generates
     server keys + per-device client configs (phone/laptop) so you can VPN
     INTO this machine from anywhere, and optionally route this PC's traffic
     through a VPS exit node.
  2. EXIT-NODE: apply a client config (from your VPS) on this PC with one
     click — wg-quick up wg0. Traffic is then tunneled through the VPS.

Requires wireguard-tools (wg, wg-quick). The manager auto-installs it where
possible (apt / brew / winget / choco) and reports clear instructions otherwise.
"""
import subprocess, platform, os, json, base64, struct, shutil

WG_DIR = os.path.join(os.path.dirname(__file__), "wg")
os.makedirs(WG_DIR, exist_ok=True)
SERVER_CONF = os.path.join(WG_DIR, "wg0-server.conf")
CLIENT_CONF = os.path.join(WG_DIR, "wg0-client.conf")
KEYS_FILE = os.path.join(WG_DIR, "keys.json")

def _run(cmd, timeout=60, shell=False):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, shell=shell)
        return {"ok": r.returncode == 0, "stdout": r.stdout, "stderr": r.stderr, "returncode": r.returncode}
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "returncode": -1}

def has_wireguard():
    return bool(shutil.which("wg")) or os.path.exists(r"C:\Program Files\WireGuard\wg.exe")

def install_wireguard():
    os_name = platform.system()
    if has_wireguard():
        return {"ok": True, "alreadyInstalled": True}
    if os_name == "Linux":
        r = _run(["bash", "-c", "apt-get update -qq && apt-get install -y -qq wireguard-tools 2>&1 | tail -5"], timeout=180)
        return {"ok": has_wireguard(), "output": r["stdout"] + r["stderr"]}
    elif os_name == "Darwin":
        r = _run(["bash", "-c", "brew install wireguard-tools 2>&1 | tail -5"], timeout=180)
        return {"ok": has_wireguard(), "output": r["stdout"] + r["stderr"]}
    elif os_name == "Windows":
        r = _run(["winget", "install", "--id", "WireGuard.WireGuard", "-e", "--accept-source-agreements", "--accept-package-agreements"], timeout=180)
        return {"ok": r["ok"], "output": r["stdout"] + r["stderr"],
                "hint": "If winget fails, download from https://wireguard.com/install/ and re-run."}
    return {"ok": False, "error": f"Unsupported platform: {os_name}"}

def _gen_keypair():
    """Generate X25519 keypair via wg genkey/pubkey (pure stdlib fallback)."""
    if has_wireguard():
        priv = subprocess.run(["wg", "genkey"], capture_output=True, text=True).stdout.strip()
        pub = subprocess.run(["wg", "pubkey"], input=priv, capture_output=True, text=True).stdout.strip()
        return priv, pub
    # Fallback: cryptography lib
    try:
        from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
        from cryptography.hazmat.primitives import serialization
        priv_obj = X25519PrivateKey.generate()
        priv = priv_obj.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
        pub = priv_obj.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        return base64.b64encode(priv).decode(), base64.b64encode(pub).decode()
    except ImportError:
        raise RuntimeError("WireGuard not installed and 'cryptography' lib missing. Install wireguard-tools first.")

def _load_keys():
    if os.path.exists(KEYS_FILE):
        with open(KEYS_FILE) as f: return json.load(f)
    return {}

def _save_keys(k):
    with open(KEYS_FILE, "w") as f: json.dump(k, f, indent=2)
    os.chmod(KEYS_FILE, 0o600)

def init_mesh(endpoint: str, client_name: str = "phone", client_ip: str = "10.8.0.2"):
    """Create server + first client config. Returns both configs + QR-ready payload."""
    server_priv, server_pub = _gen_keypair()
    client_priv, client_pub = _gen_keypair()
    server_conf = f"""[Interface]
PrivateKey = {server_priv}
Address = 10.8.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# {client_name}
PublicKey = {client_pub}
AllowedIPs = {client_ip}/32
"""
    client_conf = f"""[Interface]
PrivateKey = {client_priv}
Address = {client_ip}/32
DNS = 1.1.1.1

[Peer]
PublicKey = {server_pub}
Endpoint = {endpoint}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"""
    with open(SERVER_CONF, "w") as f: f.write(server_conf)
    with open(CLIENT_CONF, "w") as f: f.write(client_conf)
    keys = _load_keys()
    keys.update({"server_pub": server_pub, "server_priv": server_priv, "client_pub": client_pub,
                 "client_priv": client_priv, "endpoint": endpoint, "client_ip": client_ip, "client_name": client_name})
    _save_keys(keys)
    return {"ok": True, "serverConf": server_conf, "clientConf": client_conf, "endpoint": endpoint,
            "hint": "Copy serverConf to your VPS/PC running WireGuard, or run this PC as the hub with 'connect'."}

def apply_client_config(config_text: str):
    """Write an exit-node client config and bring the tunnel up (one-click VPN)."""
    with open(CLIENT_CONF, "w") as f: f.write(config_text)
    return connect()

def connect():
    if not has_wireguard():
        inst = install_wireguard()
        if not inst.get("ok"):
            return {"ok": False, "error": "WireGuard not installed", "install": inst}
    os_name = platform.system()
    if os_name == "Windows":
        # WireGuard GUI service mode: use wg-quick via the bundled exe, or tunnel service
        r = _run([r"C:\Program Files\WireGuard\wg.exe", "show", "wg0"], timeout=10)
        if r["ok"]:
            return {"ok": True, "alreadyUp": True}
        r = _run(["wg-quick", "up", CLIENT_CONF], timeout=30)
        if not r["ok"]:
            r = _run([r"C:\Program Files\WireGuard\wg-quick.exe", "up", CLIENT_CONF], timeout=30)
        return {"ok": r["ok"], "output": r["stdout"] + r["stderr"]}
    else:
        r = _run(["wg-quick", "up", CLIENT_CONF], timeout=30)
        return {"ok": r["ok"], "output": r["stdout"] + r["stderr"]}

def disconnect():
    os_name = platform.system()
    if os_name == "Windows":
        r = _run(["wg-quick", "down", CLIENT_CONF], timeout=30)
        if not r["ok"]:
            r = _run([r"C:\Program Files\WireGuard\wg-quick.exe", "down", CLIENT_CONF], timeout=30)
        return {"ok": r["ok"], "output": r["stdout"] + r["stderr"]}
    r = _run(["wg-quick", "down", CLIENT_CONF], timeout=30)
    return {"ok": r["ok"], "output": r["stdout"] + r["stderr"]}

def status():
    r = _run(["wg", "show"], timeout=10)
    up = r["ok"] and "interface" in r["stdout"]
    # Public IP check to prove the tunnel works
    pub_ip = None
    if up:
        try:
            import urllib.request
            pub_ip = urllib.request.urlopen("https://ifconfig.me/ip", timeout=8).read().decode().strip()
        except Exception:
            pass
    return {"wireguardInstalled": has_wireguard(), "tunnelUp": up, "wgShow": r["stdout"][:2000], "publicIp": pub_ip,
            "hasServerConf": os.path.exists(SERVER_CONF), "hasClientConf": os.path.exists(CLIENT_CONF)}

def kill_switch(enable: bool):
    """Block non-VPN traffic via firewall (Linux iptables / Windows firewall)."""
    os_name = platform.system()
    if os_name == "Linux":
        if enable:
            r = _run(["bash", "-c", "iptables -P OUTPUT DROP; iptables -A OUTPUT -o wg0 -j ACCEPT; iptables -A OUTPUT -o lo -j ACCEPT"], timeout=15)
        else:
            r = _run(["bash", "-c", "iptables -P OUTPUT ACCEPT"], timeout=15)
        return {"ok": r["ok"], "output": r["stdout"] + r["stderr"]}
    return {"ok": False, "error": "Kill switch supported on Linux in this build; use your OS firewall on other platforms."}
