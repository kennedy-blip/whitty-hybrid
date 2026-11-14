"use client";
import { useEffect, useState } from "react";
import { bfetch } from "@/lib/bridge-client";

export default function VpnPanel() {
  const [status, setStatus] = useState<any>(null);
  const [endpoint, setEndpoint] = useState("");
  const [generated, setGenerated] = useState<any>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");

  async function refresh() {
    try { const r = await bfetch("/api/vpn/status"); setStatus(await r.json()); } catch {}
  }
  useEffect(() => { refresh(); const i = setInterval(refresh, 8000); return () => clearInterval(i); }, []);

  async function generate() {
    setBusy(true);
    const r = await bfetch("/api/vpn/generate", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ endpoint }) });
    setGenerated(await r.json()); setBusy(false);
  }
  async function connect(config?: string) {
    setBusy(true); setMsg("Connecting…");
    const r = await bfetch("/api/vpn/connect", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(config ? { config } : {}) });
    const d = await r.json();
    setMsg(d.ok ? "✅ VPN connected on your PC." : `❌ ${d.hint || d.error || d.message || (d.requiresApproval ? "Approval required." : "Failed — is the daemon running?")}`);
    setBusy(false); refresh();
  }
  async function disconnect() {
    setBusy(true);
    await bfetch("/api/vpn/disconnect", { method: "POST" });
    setMsg("VPN disconnected."); setBusy(false); refresh();
  }
  function download() {
    const blob = new Blob([generated.config], { type: "text/plain" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "whitty-vpn.conf"; a.click();
  }

  const up = status?.tunnelUp;
  return (
    <div className="rounded-xl border border-violet-500/30 bg-violet-500/5 p-4">
      <div className="flex items-center justify-between">
        <div className="text-sm font-bold">🔐 One-Click VPN (WireGuard)</div>
        <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${up ? "bg-emerald-500/20 text-emerald-300" : "bg-slate-700 text-slate-300"}`}>
          {up ? "● TUNNEL UP" : "○ OFFLINE"}
        </span>
      </div>
      <p className="mt-1 text-xs text-slate-400">Click connect and the daemon installs WireGuard on your PC and brings the tunnel up. Generate a config to add your phone/laptop too.</p>
      {status?.publicIp && <div className="mt-2 text-xs text-emerald-300">Public IP via tunnel: <b>{status.publicIp}</b></div>}
      {status?.wireguardInstalled === false && <div className="mt-2 text-xs text-amber-300">WireGuard not installed yet — Connect will auto-install it.</div>}
      <div className="mt-3 flex flex-wrap gap-2">
        <button onClick={() => connect()} disabled={busy} className="rounded-lg bg-violet-600 px-4 py-2 text-xs font-bold hover:bg-violet-500 disabled:opacity-50">⚡ Connect VPN on My PC</button>
        <button onClick={disconnect} disabled={busy} className="rounded-lg bg-slate-700 px-4 py-2 text-xs font-bold hover:bg-slate-600 disabled:opacity-50">Disconnect</button>
      </div>
      <div className="mt-4 border-t border-slate-800 pt-3">
        <div className="text-xs font-semibold text-slate-300">Generate device config</div>
        <div className="mt-2 flex gap-2">
          <input value={endpoint} onChange={(e) => setEndpoint(e.target.value)} placeholder="Server endpoint e.g. 203.0.113.10:51820"
            className="flex-1 rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-xs outline-none focus:border-violet-500" />
          <button onClick={generate} disabled={busy || !endpoint} className="rounded-lg bg-slate-700 px-3 py-2 text-xs font-semibold hover:bg-slate-600 disabled:opacity-50">Generate</button>
        </div>
        {generated?.config && (
          <div className="mt-3 space-y-3">
            <div className="flex items-start gap-3">
              {generated.qr && <img src={generated.qr} alt="WireGuard QR" className="h-28 w-28 rounded-lg border border-slate-700 bg-white p-1" />}
              <div className="flex-1">
                <div className="text-[11px] text-slate-400">Scan with the WireGuard app on your phone, or download the .conf</div>
                <button onClick={download} className="mt-2 rounded-lg bg-violet-600 px-3 py-1.5 text-xs font-semibold hover:bg-violet-500">⬇ Download .conf</button>
                <button onClick={() => connect(generated.config)} disabled={busy} className="ml-2 rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold hover:bg-emerald-500 disabled:opacity-50">Apply to My PC</button>
              </div>
            </div>
            <pre className="max-h-40 overflow-auto rounded-lg bg-slate-950 p-2 text-[10px] text-violet-200">{generated.config}</pre>
          </div>
        )}
      </div>
      {msg && <div className="mt-3 text-xs text-slate-300">{msg}</div>}
    </div>
  );
}
