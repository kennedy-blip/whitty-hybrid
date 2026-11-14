"use client";
import { useEffect, useState } from "react";
import { getBridgeUrl, setBridgeUrl, bjson } from "@/lib/bridge-client";

export default function BridgeSetup({ onStatus }: { onStatus?: (s: any) => void }) {
  const [open, setOpen] = useState(false);
  const [url, setUrl] = useState("");
  const [saved, setSaved] = useState("");
  const [testing, setTesting] = useState(false);
  const [result, setResult] = useState<any>(null);

  useEffect(() => {
    const savedUrl = getBridgeUrl();
    setUrl(savedUrl); setSaved(savedUrl);
    if (!savedUrl) setOpen(true);
  }, []);

  async function test(target?: string) {
    setTesting(true); setResult(null);
    try {
      const prev = getBridgeUrl();
      if (target !== undefined) setBridgeUrl(target);
      const s = await bjson("/api/bridge/status");
      setResult(s?.ok ? { ok: true, vpn: s?.data?.vpn } : { ok: false, err: s?.data?.error || "unreachable" });
      onStatus?.(s);
      if (!s?.ok && target === undefined) setBridgeUrl(prev);
    } catch (e: any) { setResult({ ok: false, err: String(e?.message || e) }); }
    setTesting(false);
  }

  function save() {
    setBridgeUrl(url);
    setSaved(url.trim().replace(/\/$/, ""));
    test();
  }

  return (
    <div className="rounded-xl border border-sky-500/30 bg-sky-500/5 p-3">
      <div className="flex items-center justify-between">
        <div className="text-xs font-bold text-sky-300">🔗 Connect my PC</div>
        <button onClick={() => setOpen(!open)} className="text-[11px] text-slate-400 hover:text-slate-200">{open ? "hide" : "settings"}</button>
      </div>
      {!open && (
        <div className="mt-1 truncate text-[11px] text-slate-400">
          {saved ? <>tunnel: <span className="text-slate-200">{saved}</span></> : "not configured — click settings"}
        </div>
      )}
      {open && (
        <div className="mt-2 space-y-2">
          <p className="text-[11px] leading-relaxed text-slate-400">
            Paste your daemon URL. On the same Wi-Fi: <code className="text-slate-200">http://localhost:8765</code>.
            From anywhere: your Cloudflare Tunnel URL (<code className="text-slate-200">https://….trycloudflare.com</code>).
          </p>
          <input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://your-tunnel.trycloudflare.com"
            className="w-full rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-xs outline-none focus:border-sky-500" />
          <div className="flex gap-2">
            <button onClick={save} disabled={testing} className="rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-bold hover:bg-sky-500 disabled:opacity-50">
              {testing ? "Testing…" : "Save & Test"}
            </button>
            <button onClick={() => { setBridgeUrl(""); setUrl(""); setSaved(""); setResult(null); }}
              className="rounded-lg bg-slate-700 px-3 py-1.5 text-xs font-semibold hover:bg-slate-600">Use default</button>
          </div>
          {result && (
            <div className={`text-[11px] ${result.ok ? "text-emerald-300" : "text-red-300"}`}>
              {result.ok ? "✅ Connected — daemon is reachable." : `❌ Not reachable (${result.err}). Is the daemon running and the tunnel URL current?`}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
