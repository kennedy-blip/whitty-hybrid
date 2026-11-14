"use client";
import { useCallback, useEffect, useState } from "react";
import ChatPanel from "@/components/ChatPanel";
import ToolPanel from "@/components/ToolPanel";
import VpnPanel from "@/components/VpnPanel";
import AuditPanel from "@/components/AuditPanel";
import BridgeSetup from "@/components/BridgeSetup";
import { bjson, getBridgeUrl } from "@/lib/bridge-client";

export default function Home() {
  const [bridge, setBridge] = useState<any>(null);
  const [tab, setTab] = useState<"tools" | "audit">("tools");

  const poll = useCallback(() => {
    bjson("/api/bridge/status").then(setBridge).catch(() => setBridge({ ok: false }));
  }, []);

  useEffect(() => {
    poll();
    const i = setInterval(poll, 10000);
    window.addEventListener("whitty:bridge-changed", poll);
    return () => { clearInterval(i); window.removeEventListener("whitty:bridge-changed", poll); };
  }, [poll]);

  const online = bridge?.ok;
  const tunnel = getBridgeUrl();
  return (
    <div className="flex h-screen flex-col">
      <header className="flex items-center justify-between border-b border-slate-800 px-5 py-3">
        <div>
          <h1 className="text-lg font-black tracking-tight">⚡ Whitty <span className="text-sky-400">Hybrid</span></h1>
          <p className="text-[11px] text-slate-500">AI Diagnostic Agent — Cloud Brain × Local Hands</p>
        </div>
        <div className="flex items-center gap-3">
          <span className={`rounded-full px-3 py-1 text-[11px] font-semibold ${online ? "bg-emerald-500/20 text-emerald-300" : "bg-red-500/20 text-red-300"}`}>
            {online ? "● Daemon Online" : "○ Daemon Offline"}
          </span>
          {!online && <span className="text-[11px] text-slate-500">{tunnel ? "Tunnel set — start the daemon" : "Start it: python daemon/main.py"}</span>}
        </div>
      </header>
      <div className="grid flex-1 grid-cols-1 lg:grid-cols-[420px_1fr] overflow-hidden">
        <aside className="overflow-y-auto border-r border-slate-800 p-4 space-y-4">
          <BridgeSetup onStatus={setBridge} />
          <VpnPanel />
          <div className="flex gap-2">
            <button onClick={() => setTab("tools")} className={`rounded-lg px-3 py-1.5 text-xs font-bold ${tab === "tools" ? "bg-sky-600" : "bg-slate-800"}`}>Tools</button>
            <button onClick={() => setTab("audit")} className={`rounded-lg px-3 py-1.5 text-xs font-bold ${tab === "audit" ? "bg-sky-600" : "bg-slate-800"}`}>Audit Trail</button>
          </div>
          {tab === "tools" ? <ToolPanel /> : <AuditPanel />}
        </aside>
        <main className="overflow-hidden"><ChatPanel /></main>
      </div>
    </div>
  );
}
