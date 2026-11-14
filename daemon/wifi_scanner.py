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
