// Server-side client for the Local Python Daemon (The Hands).
const DEFAULT_URL = (process.env.BRIDGE_URL || "http://localhost:8765").replace(/\/$/, "");
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || "";

// Only these hosts may be used as a bridge target when the browser supplies one
// (lets you point at a fresh Cloudflare Tunnel URL without redeploying).
const ALLOWED_HOSTS = [
  /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i,
  /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/i,
  /^https:\/\/[a-z0-9-]+\.ngrok-free\.app$/i,
  /^https:\/\/[a-z0-9-]+\.ngrok\.io$/i,
  /^https:\/\/[a-z0-9-]+\.loca\.lt$/i,
  /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)*\.ts\.net$/i,
];

export function resolveBridgeUrl(override?: string | null): string {
  if (!override) return DEFAULT_URL;
  const url = String(override).trim().replace(/\/$/, "");
  if (!url) return DEFAULT_URL;
  if (url === DEFAULT_URL) return url;
  return ALLOWED_HOSTS.some((re) => re.test(url)) ? url : DEFAULT_URL;
}

export function bridgeUrlFromRequest(req: Request): string {
  return resolveBridgeUrl(req.headers.get("x-bridge-url"));
}

export async function bridgeFetch(path: string, init: RequestInit = {}, baseUrl?: string) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 25000);
  const base = (baseUrl || DEFAULT_URL).replace(/\/$/, "");
  try {
    const res = await fetch(`${base}${path}`, {
      ...init,
      signal: ctrl.signal,
      cache: "no-store",
      headers: { "Content-Type": "application/json", ...(BRIDGE_TOKEN ? { Authorization: `Bearer ${BRIDGE_TOKEN}` } : {}), ...(init.headers || {}) },
    });
    const text = await res.text();
    let data: any; try { data = JSON.parse(text); } catch { data = { raw: text.slice(0, 2000) }; }
    return { ok: res.ok, status: res.status, data };
  } catch (e: any) {
    return { ok: false, status: 0, data: { error: "bridge_unreachable", detail: String(e?.message || e), hint: "Is the daemon running on your PC? cd daemon && python main.py — and does the tunnel URL match?" } };
  } finally { clearTimeout(t); }
}

export async function bridgeStatus(baseUrl?: string) {
  return bridgeFetch("/status", {}, baseUrl);
}

// `approved` MUST be a top-level field of the request body — that is what the
// daemon's safety gate reads (body["approved"]). Nesting it inside `args` makes
// every mutating call bounce back with "needs human approval".
export async function bridgeExecute(
  tool: string,
  args: Record<string, any> = {},
  baseUrl?: string,
  approved?: boolean,
) {
  const body: Record<string, any> = { tool, args };
  if (approved !== undefined) body.approved = approved;
  return bridgeFetch("/execute", { method: "POST", body: JSON.stringify(body) }, baseUrl);
}
