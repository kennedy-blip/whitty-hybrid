"use client";
import { useState } from "react";
import { bfetch } from "@/lib/bridge-client";

type ToolDef = { id: string; label: string; desc: string; endpoint: string; inputLabel: string; placeholder: string; mutating?: boolean; argKey?: string };

const CLOUD: ToolDef[] = [
  { id: "dns", label: "DNS Trace", desc: "A / CNAME / MX / TXT across resolvers", endpoint: "/api/cloud/dns", inputLabel: "Domain", placeholder: "example.com" },
  { id: "ssl", label: "SSL Audit", desc: "Expiry, issuer, chain validity", endpoint: "/api/cloud/ssl", inputLabel: "Domain", placeholder: "example.com" },
  { id: "cors", label: "CORS & Headers", desc: "HSTS, CSP, CORS roadblocks", endpoint: "/api/cloud/cors", inputLabel: "URL", placeholder: "https://api.example.com" },
  { id: "health", label: "API Health", desc: "Latency triage, 3 samples", endpoint: "/api/cloud/health", inputLabel: "URL", placeholder: "https://api.example.com/health" },
];

const LOCAL: ToolDef[] = [
  { id: "scan_wifi", label: "Wi-Fi Scan", desc: "SSID, BSSID, RSSI, channels, congestion", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "" },
  { id: "adapter_power_status", label: "Adapter Power", desc: "Aggressive sleep detection", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "" },
  { id: "list_ports", label: "Ports & PIDs", desc: "TCP/UDP → PID → path", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "" },
  { id: "system_overview", label: "System Overview", desc: "CPU, memory, interfaces, IPs", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "" },
  { id: "wifi_profile_details", label: "Sign-in / 802.1X Profile", desc: "EAP method, identity, PSK, portal needs", endpoint: "/api/bridge/execute", inputLabel: "SSID (blank = all)", placeholder: "OfficeWiFi", mutating: true, argKey: "ssid" },
  { id: "captive_portal_status", label: "Captive Portal Check", desc: "Is a sign-in page blocking internet?", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "" },
  { id: "wifi_saved_passwords", label: "Saved Wi-Fi Passwords", desc: "Reveal stored keys from the OS key store", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "", mutating: true },
  { id: "network_recovery", label: "Network Recovery", desc: "Flush DNS / renew DHCP / Winsock", endpoint: "/api/bridge/execute", inputLabel: "Action", placeholder: "flush_dns", mutating: true },
  { id: "disable_adapter_sleep", label: "Disable Sleep", desc: "Fix random Wi-Fi drops", endpoint: "/api/bridge/execute", inputLabel: "", placeholder: "", mutating: true },
];

function ToolCard({ tool, cloud }: { tool: ToolDef; cloud: boolean }) {
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [approval, setApproval] = useState<any>(null);

  async function run(approved = false) {
    setLoading(true);
    try {
      const body = cloud
        ? { domain: input, url: input }
        : {
            tool: tool.id,
            args:
              tool.id === "network_recovery"
                ? { action: input || "flush_dns" }
                : tool.argKey && input
                  ? { [tool.argKey]: input }
                  : {},
            approved,
          };
      const res = await bfetch(tool.endpoint, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const data = await res.json();
      if (data.requiresApproval) { setApproval(data); }
      else { setResult(data); setApproval(null); }
    } finally { setLoading(false); }
  }

  return (
    <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-3">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-sm font-semibold">{tool.label} {tool.mutating && <span className="ml-1 rounded bg-amber-500/20 px-1.5 py-0.5 text-[10px] text-amber-300">MUTATING</span>}</div>
          <div className="text-xs text-slate-400">{tool.desc}</div>
        </div>
        {tool.inputLabel ? (
          <div className="flex gap-2">
            <input value={input} onChange={(e) => setInput(e.target.value)} placeholder={tool.placeholder}
              className="w-40 rounded-lg border border-slate-700 bg-slate-950 px-2 py-1.5 text-xs outline-none focus:border-sky-500" />
            <button onClick={() => run()} disabled={loading} className="rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-semibold hover:bg-sky-500 disabled:opacity-50">
              {loading ? "Running…" : "Run"}
            </button>
          </div>
        ) : (
          <button onClick={() => run()} disabled={loading} className="rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-semibold hover:bg-sky-500 disabled:opacity-50">
            {loading ? "Running…" : "Run"}
          </button>
        )}
      </div>
      {approval && (
        <div className="mt-3 rounded-lg border border-amber-500/40 bg-amber-500/10 p-3">
          <div className="text-xs font-semibold text-amber-200">⚠️ Approval required — {approval.tool}</div>
          <div className="mt-1 text-xs text-amber-100/80">{approval.message}</div>
          <div className="mt-2 flex gap-2">
            <button onClick={() => run(true)} className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold hover:bg-emerald-500">Approve & Run</button>
            <button onClick={() => setApproval(null)} className="rounded-lg bg-slate-700 px-3 py-1.5 text-xs font-semibold hover:bg-slate-600">Reject</button>
          </div>
        </div>
      )}
      {result && (
        <pre className="mt-3 max-h-64 overflow-auto rounded-lg bg-slate-950 p-3 text-[11px] leading-relaxed text-emerald-200">{JSON.stringify(result, null, 2)}</pre>
      )}
    </div>
  );
}

export default function ToolPanel() {
  return (
    <div className="space-y-4">
      <div>
        <div className="mb-2 text-xs font-bold uppercase tracking-widest text-sky-400">☁️ Cloud Sentinel (Vercel)</div>
        <div className="space-y-2">{CLOUD.map((t) => <ToolCard key={t.id} tool={t} cloud />)}</div>
      </div>
      <div>
        <div className="mb-2 text-xs font-bold uppercase tracking-widest text-emerald-400">🖥️ Local Bridge (Your PC)</div>
        <div className="space-y-2">{LOCAL.map((t) => <ToolCard key={t.id} tool={t} cloud={false} />)}</div>
      </div>
    </div>
  );
}
