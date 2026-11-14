"use client";
import { useEffect, useState } from "react";
import { bjson } from "@/lib/bridge-client";
export default function AuditPanel() {
  const [data, setData] = useState<any>(null);
  useEffect(() => {
    const load = () => bjson("/api/audit").then(setData).catch(() => {});
    load();
    window.addEventListener("whitty:bridge-changed", load);
    return () => window.removeEventListener("whitty:bridge-changed", load);
  }, []);
  const all = [...(data?.local || []), ...(data?.cloud || [])].slice(0, 30);
  const backend = data?.backend;
  const badge = backend ? (
    <div className="mb-2 text-[10px] uppercase tracking-wider text-slate-500">
      cloud trail: <span className={backend === "supabase" ? "text-emerald-400" : "text-amber-400"}>{backend}</span>
      {backend === "memory" && " (per-instance — set SUPABASE_URL to persist)"}
    </div>
  ) : null;
  if (!all.length) return <div>{badge}<div className="text-xs text-slate-500">No audit entries yet — run a tool to see the trail.</div></div>;
  return (
    <div className="space-y-1.5">
      {badge}
      {all.map((e: any, i: number) => (
        <div key={i} className="flex items-center justify-between rounded-lg bg-slate-900/60 px-3 py-2 text-[11px]">
          <span className="font-mono text-sky-300">{e.tool}</span>
          <span className="text-slate-500">{new Date(e.ts * 1000 || e.ts).toLocaleTimeString()}</span>
          <span className={e.approved === false ? "text-red-400" : e.approved === true ? "text-emerald-400" : "text-slate-400"}>
            {e.approved === false ? "✗ rejected" : e.approved === true ? "✓ approved" : "auto"}
          </span>
        </div>
      ))}
    </div>
  );
}
