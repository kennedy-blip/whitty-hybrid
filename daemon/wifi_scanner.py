"""Wi-Fi environment & interference auditing — decrypts full scan details."""
import subprocess, platform, re, json

def _run(cmd, timeout=20):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout + r.stderr
    except Exception as e:
        return f"ERROR: {e}"

def scan_wifi():
    os_name = platform.system()
    if os_name == "Windows":
        return _scan_windows()
    elif os_name == "Darwin":
        return _scan_macos()
    else:
        return _scan_linux()

def _scan_windows():
    # netsh wlan show networks mode=bssid — full BSSID, channel, signal, auth, radio type
    out = _run(["netsh", "wlan", "show", "networks", "mode=bssid"])
    networks = []
    current = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("SSID ") and ":" in line:
            if current: networks.append(current)
            current = {"ssid": line.split(":", 1)[1].strip(), "bssids": []}
        elif line.startswith("BSSID ") and current is not None:
            current["bssids"].append({"bssid": line.split(":", 1)[1].strip()})
        elif current and current["bssids"]:
            b = current["bssids"][-1]
            if line.startswith("Signal"): b["signal"] = line.split(":", 1)[1].strip()
            elif line.startswith("Channel"): b["channel"] = line.split(":", 1)[1].strip()
            elif line.startswith("Radio type"): b["radioType"] = line.split(":", 1)[1].strip()
            elif line.startswith("Authentication"): b["auth"] = line.split(":", 1)[1].strip()
            elif line.startswith("Basic rates"): b["basicRates"] = line.split(":", 1)[1].strip()
            elif line.startswith("Other rates"): b["otherRates"] = line.split(":", 1)[1].strip()
    if current: networks.append(current)
    # Channel congestion analysis
    chan_counts = {}
    for n in networks:
        for b in n.get("bssids", []):
            ch = b.get("channel", "?")
            chan_counts[ch] = chan_counts.get(ch, 0) + 1
    congested = sorted(chan_counts.items(), key=lambda x: -x[1])[:3]
    return {"platform": "Windows", "networks": networks, "totalNetworks": len(networks),
            "channelCongestion": [{"channel": k, "apCount": v} for k, v in congested],
            "recommendation": _recommend(congested)}

def _scan_macos():
    out = _run(["/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-s"])
    rows = []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 4:
            rows.append({"ssid": parts[0], "bssid": parts[1] if len(parts) > 1 else "", "signal": parts[2] if len(parts) > 2 else "", "channel": parts[3] if len(parts) > 3 else ""})
    return {"platform": "macOS", "networks": rows, "totalNetworks": len(rows)}

def _scan_linux():
    out = _run(["iw", "dev", "scan"])
    networks, cur = [], None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("BSS ") and cur: networks.append(cur); cur = {"bssid": line.split()[1]}
        elif line.startswith("BSS "): cur = {"bssid": line.split()[1]}
        elif cur is not None:
            if line.startswith("SSID:"): cur["ssid"] = line.split(":", 1)[1].strip()
            elif line.startswith("signal:"): cur["signal"] = line.split(":", 1)[1].strip()
            elif line.startswith("freq:"): cur["freq"] = line.split(":", 1)[1].strip()
            elif line.startswith("DS Parameter set: channel"): cur["channel"] = line.split()[-1]
    if cur: networks.append(cur)
    return {"platform": "Linux", "networks": networks, "totalNetworks": len(networks)}

def _recommend(congested):
    if not congested: return "No congestion data available."
    top, count = congested[0]
    if count > 4: return f"Channel {top} is heavily congested ({count} APs). Prefer 5GHz channels 36-48 or 149-161."
    return f"Channel {top} has the most APs ({count}). Consider switching to a less crowded channel."

def adapter_power_status():
    """Detect aggressive OS power-saving on the wireless adapter."""
    os_name = platform.system()
    if os_name == "Windows":
        out = _run(["powershell", "-Command",
            "Get-NetAdapter | Where-Object MediaType -eq '802.11' | Select-Object Name,Status,LinkSpeed | ConvertTo-Json -Compress"])
        try: adapters = json.loads(out) if out.strip() else []
        except Exception: adapters = [{"raw": out}]
        # Power management setting
        pm = _run(["powershell", "-Command",
            "Get-NetAdapterAdvancedProperty -Name '*' -RegistryKeyword '*Save*','*Power*' -ErrorAction SilentlyContinue | Select-Object Name,DisplayValue | ConvertTo-Json -Compress"])
        return {"platform": "Windows", "adapters": adapters, "powerSettingsRaw": pm[:2000],
                "aggressiveSleepDetected": "Save" in pm or "Power" in pm,
                "hint": "Disable 'Allow the computer to turn off this device to save power' in Device Manager > Wi-Fi Adapter > Power Management."}
    elif os_name == "Linux":
        out = _run(["iwconfig"])
        return {"platform": "Linux", "iwconfig": out[:3000],
                "hint": "Check 'iw dev wlan0 set power_save off' and NetworkManager wifi.powersave."}
    else:
        return {"platform": os_name, "hint": "Check System Settings > Wi-Fi > Advanced > Disable power saving."}

def disable_adapter_sleep():
    """Mutating: disable aggressive power saving (requires approval in UI)."""
    os_name = platform.system()
    if os_name == "Windows":
        out = _run(["powershell", "-Command",
            "Disable-NetAdapterPowerSaving -Name '*' -ErrorAction SilentlyContinue; 'done'"])
        return {"ok": True, "output": out, "note": "Power saving disabled via Disable-NetAdapterPowerSaving. Reboot adapter if drops persist."}
    elif os_name == "Linux":
        out = _run(["bash", "-c", "iw dev wlan0 set power_save off 2>&1; iwconfig wlan0 power off 2>&1"])
        return {"ok": True, "output": out}
    return {"ok": False, "error": f"Unsupported platform: {os_name}"}


KEY_RE = re.compile(r"Key Content\s*:\s*(.+)", re.IGNORECASE)
PROFILE_RE = re.compile(r"^\s*(?:All User Profile|Profile)\s*:\s*(.+?)\s*$", re.IGNORECASE)


def saved_passwords():
    """Sensitive/mutating: read saved Wi-Fi profiles back out of the OS key store.

    Windows : netsh wlan show profile name="X" key=clear  -> "Key Content"
    macOS   : security find-generic-password -wa "<SSID>" (may prompt for keychain access)
    Linux   : /etc/NetworkManager/system-connections/*.nmconnection (needs root)

    Requires human approval in the UI because it exposes real credentials.
    """
    os_name = platform.system()
    if os_name == "Windows":
        return _saved_windows()
    if os_name == "Darwin":
        return _saved_macos()
    return _saved_linux()


def _saved_windows():
    listing = _run(["netsh", "wlan", "show", "profiles"])
    names, seen = [], set()
    for line in listing.splitlines():
        m = PROFILE_RE.match(line)
        if m:
            name = m.group(1).strip()
            if name and name.lower() not in seen:
                seen.add(name.lower())
                names.append(name)

    networks = []
    for name in names:
        out = _run(["netsh", "wlan", "show", "profile", f'name={name}', "key=clear"])
        password = None
        auth = None
        cipher = None
        for line in out.splitlines():
            if password is None:
                km = KEY_RE.search(line)
                if km:
                    password = km.group(1).strip()
                    continue
            low = line.strip()
            if low.lower().startswith("authentication"):
                auth = low.split(":", 1)[1].strip() if ":" in low else auth
            elif low.lower().startswith("cipher"):
                cipher = low.split(":", 1)[1].strip() if ":" in low else cipher
        needs_admin = password is None and "elevat" in out.lower()
        networks.append({
            "ssid": name,
            "password": password,
            "auth": auth,
            "cipher": cipher,
            "open": (auth or "").lower().startswith("open"),
            "note": "run the daemon as Administrator to read this password" if needs_admin else None,
        })
    return {
        "platform": "Windows",
        "count": len(networks),
        "networks": networks,
        "warning": "These are real saved credentials. Nothing is stored by Whitty; only the local audit log records that this tool ran.",
    }


def _saved_macos():
    listing = _run(["/usr/sbin/networksetup", "-listpreferredwirelessnetworks", "en0"])
    names = [l.strip() for l in listing.splitlines()[1:] if l.strip()]
    networks = []
    for name in names:
        pw = _run(["/usr/bin/security", "find-generic-password", "-D", "AirPort network password", "-a", name, "-w"]).strip()
        networks.append({"ssid": name, "password": pw or None,
                         "note": None if pw else "keychain denied or not saved - allow access when macOS prompts"})
    return {"platform": "macOS", "count": len(networks), "networks": networks,
            "warning": "These are real saved credentials from your keychain."}


def _saved_linux():
    import glob
    entries = []
    for path in glob.glob("/etc/NetworkManager/system-connections/*"):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                text = fh.read()
        except PermissionError:
            entries.append({"file": path, "error": "permission denied - run the daemon with sudo"})
            continue
        except Exception as exc:
            entries.append({"file": path, "error": str(exc)})
            continue
        ssid = psk = None
        for line in text.splitlines():
            if line.startswith("ssid="):
                ssid = line.split("=", 1)[1].strip()
            elif line.startswith("psk="):
                psk = line.split("=", 1)[1].strip()
        entries.append({"ssid": ssid or path.rsplit("/", 1)[-1], "password": psk,
                        "note": None if psk else "enterprise/open network or no stored PSK"})
    return {"platform": "Linux", "count": len(entries), "networks": entries,
            "warning": "These are real saved credentials."}


# ---------------------------------------------------------------------------
# Saved profile deep-dive: enterprise / 802.1X / captive-portal networks.
# These are the ones where a plain PSK is not the whole story: they either
# need an identity+password, a certificate, or a browser sign-in page.
# ---------------------------------------------------------------------------
EAP_TYPES = {
    "13": "EAP-TLS (certificate)", "18": "EAP-SIM", "21": "EAP-TTLS", "23": "EAP-AKA",
    "25": "PEAP (username + password)", "43": "EAP-FAST", "50": "EAP-AKA'",
}
WLAN_PROFILE_DIRS = [
    r"C:\ProgramData\Microsoft\Wlansvc\Profiles\Interfaces",
]


def _parse_profile_xml(path):
    """Best-effort extraction from a Wlansvc profile XML (no dependencies)."""
    import xml.etree.ElementTree as ET
    try:
        root = ET.parse(path).getroot()
    except Exception as exc:
        return {"error": str(exc)}

    def text(node, tag):
        el = node.find(tag)
        return (el.text or "").strip() if el is not None and el.text else None

    ns = {"w": "http://www.microsoft.com/networking/WLAN/profile/v1",
          "w3": "http://www.microsoft.com/networking/WLAN/profile/v3",
          "e": "http://www.microsoft.com/networking/OneX/v1"}

    def find_any(tags):
        for t in tags:
            el = root.find(t, ns)
            if el is not None:
                return el
        return None

    ssid_el = root.find("w:SSIDConfig/w:SSID/w:name", ns)
    auth_el = root.find("w:MSM/w:security/w:authEncryption/w:authentication", ns)
    enc_el = root.find("w:MSM/w:security/w:authEncryption/w:encryption", ns)
    onex = root.find("w:MSM/w:security/w:OneX", ns)
    eap = root.find(".//w:EAPConfig", ns)

    eap_type = eap_method = None
    if eap is not None:
        eap_type = text(eap, "w:EAPMethod/w:Type") or eap.findtext(".//{*}Type")
        m = {}
        for el in eap.iter():
            tag = el.tag.split("}")[-1]
            if tag in ("Type", "VendorId", "AuthorId") and el.text:
                m.setdefault(tag, el.text.strip())
        eap_type = eap_type or m.get("Type")
        eap_method = EAP_TYPES.get(str(eap_type), f"EAP type {eap_type}" if eap_type else None)

    eap_user = None
    for el in root.iter():
        tag = el.tag.split("}")[-1].lower()
        if tag in ("username", "user", "identity", "alternateidentity") and el.text and el.text.strip():
            eap_user = el.text.strip()
            break

    key_material = None
    for el in root.iter():
        if el.tag.split("}")[-1] == "keyMaterial" and el.text:
            key_material = el.text.strip()
            break

    auth = text(auth_el, ".") if auth_el is not None else None
    enc = enc_el.text.strip() if enc_el is not None and enc_el.text else None
    auth = (auth_el.text or "").strip() if auth_el is not None and auth_el.text else auth

    security_mode = (
        "open" if (auth or "").lower() == "open"
        else "enterprise/802.1X" if onex is not None or (auth or "").upper() in ("WPA2-ENTERPRISE", "WPA3-ENTERPRISE")
        else "personal/PSK"
    )

    return {
        "ssid": (ssid_el.text or "").strip() if ssid_el is not None and ssid_el.text else None,
        "authentication": auth,
        "encryption": enc,
        "securityMode": security_mode,
        "requiresSignIn": security_mode != "personal/PSK",
        "oneXEnabled": onex is not None,
        "eapType": eap_type,
        "eapMethod": eap_method,
        "identity": eap_user,
        "keyMaterial": key_material,
        "profileFile": path,
    }


def wifi_profile_details(ssid=None):
    """Sensitive (mutating): deep profile for one or all saved networks.

    Reports what kind of sign-in a network needs and everything the OS will
    hand over: PSK, 802.1X/EAP method, stored identity, and whether the next
    connection will open a captive portal instead of just using a key.
    """
    os_name = platform.system()
    if os_name == "Windows":
        return _profile_details_windows(ssid)
    if os_name == "Darwin":
        base = _saved_macos()
        if ssid:
            base["networks"] = [n for n in base["networks"] if n["ssid"].lower() == ssid.lower()]
            base["count"] = len(base["networks"])
        for n in base["networks"]:
            n["securityMode"] = "personal/PSK (or open)" if n.get("password") else "unknown"
            n["requiresSignIn"] = False
        base["note"] = "macOS keeps 802.1X identities in the system keychain; check System Settings > Wi-Fi > Details > 802.1X."
        return base
    return _saved_linux()


def _profile_details_windows(ssid=None):
    import glob, os as _os
    profiles = []
    for base in WLAN_PROFILE_DIRS:
        for path in glob.glob(_os.path.join(base, "*", "*.xml")):
            info = _parse_profile_xml(path)
            if info.get("error"):
                info["ssid"] = _os.path.splitext(_os.path.basename(path))[0]
            info["ssid"] = info.get("ssid") or _os.path.splitext(_os.path.basename(path))[0]
            profiles.append(info)

    if not profiles:
        # No access to ProgramData (non-admin) — fall back to netsh summaries.
        return {"platform": "Windows", "profiles": [], "fallback": _saved_windows(),
                "note": "ProgramData profile XML not readable — run the daemon as Administrator for 802.1X/EAP detail."}

    if ssid:
        profiles = [p for p in profiles if (p.get("ssid") or "").lower() == ssid.lower()] or profiles

    for p in profiles:
        name = p.get("ssid")
        out = _run(["netsh", "wlan", "show", "profile", f"name={name}", "key=clear"])
        psk = None
        for line in out.splitlines():
            m = KEY_RE.search(line)
            if m:
                psk = m.group(1).strip()
                break
        p["password"] = psk or p.get("keyMaterial")
        p["hasStoredKey"] = bool(p["password"])
        if p.get("securityMode") == "enterprise/802.1X":
            p["note"] = (
                "802.1X network: the password lives in your identity provider, not in the profile. "
                "Windows stores an encrypted EAP blob that only your logged-in user can decrypt."
            )
        elif p.get("securityMode") == "open":
            p["note"] = "Open network — no key. If it redirects to a login page, use the Captive Portal check."
        p.pop("keyMaterial", None)

    return {
        "platform": "Windows",
        "count": len(profiles),
        "profiles": profiles,
        "summary": {
            "personal": sum(1 for p in profiles if p.get("securityMode") == "personal/PSK"),
            "enterprise": sum(1 for p in profiles if p.get("securityMode") == "enterprise/802.1X"),
            "openOrPortal": sum(1 for p in profiles if p.get("securityMode") == "open"),
        },
        "warning": "Real credentials. Whitty does not transmit them anywhere; only the audit log records that this ran.",
    }


def captive_portal_status():
    """Read-only: is the current connection stuck behind a sign-in page?"""
    import urllib.request, urllib.error, socket

    probes = [
        ("http://connectivitycheck.gstatic.com/generate_204", 204),
        ("http://captive.apple.com/hotspot-detect.html", 200),
        ("http://www.msftconnecttest.com/connecttest.txt", 200),
    ]

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    results = []
    portal = None
    for url, expect in probes:
        entry = {"probe": url, "expected": expect}
        try:
            with opener.open(url, timeout=6) as resp:
                body = resp.read(200).decode("utf-8", "ignore")
                entry.update(status=resp.status, location=resp.headers.get("Location"), body=body[:120])
                if resp.status == expect:
                    entry["verdict"] = "clean"
                else:
                    entry["verdict"] = "portal"
                    portal = portal or resp.headers.get("Location") or url
        except urllib.error.HTTPError as exc:
            entry.update(status=exc.code, location=exc.headers.get("Location", "") if exc.headers else None,
                         verdict="portal")
            portal = portal or (exc.headers.get("Location") if exc.headers else None) or url
        except Exception as exc:
            entry.update(status=None, verdict="unreachable", error=str(exc))
        results.append(entry)

    # Which SSID are we on right now?
    current = None
    if platform.system() == "Windows":
        out = _run(["netsh", "wlan", "show", "interfaces"])
        for line in out.splitlines():
            if line.strip().lower().startswith("ssid") and "bssid" not in line.strip().lower():
                current = line.split(":", 1)[1].strip()
                break
    elif platform.system() == "Darwin":
        out = _run(["/usr/sbin/airport", "-I"])
        for line in out.splitlines():
            if " SSID:" in line:
                current = line.split("SSID:", 1)[1].strip()
    else:
        out = (_run(["iwgetid", "-r"]) or "").strip()
        current = out if out and not out.startswith("ERROR") else None

    behind = portal is not None
    reachable = any(r.get("verdict") in ("clean", "portal") for r in results)
    return {
        "connectedSsid": current,
        "behindSignInPage": behind,
        "portalUrl": portal,
        "signInRequired": behind,
        "probes": results,
        "advice": (
            f"This network ({current or 'current'}) wants you to sign in at {portal} — open that URL in a browser, "
            "accept the terms, and normal internet access resumes."
            if behind else
            "Internet reachable — no captive sign-in needed on this network."
            if reachable else
            "No probe got an answer, so the state is unknown — you may be offline, on a filtered network, or behind a proxy."
        ),
    }
