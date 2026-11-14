// Server-side client for the Local Python Daemon (The Hands).
const BRIDGE_URL = (process.env.BRIDGE_URL || "http://localhost:8765").replace(/\/$/, "");
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || "";

export async function bridgeFetch(path: string, init: RequestInit = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 25000);
  try {
    const res = await fetch(`${BRIDGE_URL}${path}`, {
      ...init,
      signal: ctrl.signal,
      headers: { "Content-Type": "application/json", ...(BRIDGE_TOKEN ? { Authorization: `Bearer ${BRIDGE_TOKEN}` } : {}), ...(init.headers || {}) },
    });
    const text = await res.text();
    let data: any; try { data = JSON.parse(text); } catch { data = { raw: text }; }
    return { ok: res.ok, status: res.status, data };
  } catch (e: any) {
    return { ok: false, status: 0, data: { error: "bridge_unreachable", detail: String(e?.message || e), hint: "Start the daemon on your PC: cd daemon && python main.py" } };
  } finally { clearTimeout(t); }
}

export async function bridgeStatus() {
  return bridgeFetch("/status");
}

export async function bridgeExecute(tool: string, args: Record<string, any> = {}) {
  return bridgeFetch("/execute", { method: "POST", body: JSON.stringify({ tool, args }) });
}
