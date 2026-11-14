"use client";
import { useState } from "react";
import { useChat } from "@ai-sdk/react";
import { getBridgeUrl, bfetch } from "@/lib/bridge-client";

// Attach the current tunnel URL so the server can reach YOUR daemon.
async function bridgeFetch(input: RequestInfo | URL, init?: RequestInit) {
  const url = getBridgeUrl();
  const headers: Record<string, string> = { "Content-Type": "application/json", ...((init?.headers as Record<string, string>) || {}) };
  if (url) headers["x-bridge-url"] = url;
  return fetch(input, { ...init, headers });
}

const MUTATING_LABEL: Record<string, string> = {
  disable_adapter_sleep: "Disable Wi-Fi adapter power saving",
  kill_process: "Kill a running process",
  network_recovery: "Reset network stack (flush DNS / DHCP / Winsock)",
  vpn_connect: "Bring the WireGuard VPN up on this PC",
  vpn_disconnect: "Bring the WireGuard VPN down",
  wifi_saved_passwords: "Reveal saved Wi-Fi passwords",
  wifi_profile_details: "Read saved network profiles (keys, 802.1X identity)",
};

function ToolInvocation({ invocation }: { invocation: any }) {
  const [result, setResult] = useState<any>(invocation.state === "result" ? invocation.result : null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const needsApproval = result?.requiresApproval === true;
  const done = invocation.state === "result" && !needsApproval;

  async function decide(approved: boolean) {
    if (!approved) { setResult({ rejected: true, message: "You rejected this action." }); return; }
    setBusy(true); setError(null);
    try {
      const res = await bfetch("/api/bridge/execute", {
        method: "POST",
        body: JSON.stringify({ tool: invocation.toolName, args: result?.args ?? invocation.args ?? {}, approved: true }),
      });
      const data = await res.json();
      setResult(data);
    } catch (e: any) { setError(String(e?.message || e)); }
    setBusy(false);
  }

  return (
    <div className="mt-2 rounded-lg bg-slate-950/60 px-3 py-2 text-xs">
      <span className="font-semibold text-sky-300">🔧 {invocation.toolName}</span>
      {invocation.state !== "result" && <span className="text-amber-300"> ⏳ running…</span>}
      {done && <span className="text-emerald-300"> ✓ done</span>}
      {needsApproval && (
        <div className="mt-2 rounded-lg border border-amber-500/40 bg-amber-500/10 p-2">
          <div className="text-[11px] font-semibold text-amber-200">⚠️ Approval required</div>
          <div className="mt-0.5 text-[11px] text-amber-100/80">
            {MUTATING_LABEL[invocation.toolName] || "This action changes your PC"} — nothing has run yet.
          </div>
          <div className="mt-2 flex gap-2">
            <button onClick={() => decide(true)} disabled={busy}
              className="rounded-lg bg-emerald-600 px-3 py-1.5 text-[11px] font-bold hover:bg-emerald-500 disabled:opacity-50">
              {busy ? "Running…" : "Approve & Run"}
            </button>
            <button onClick={() => decide(false)} disabled={busy}
              className="rounded-lg bg-slate-700 px-3 py-1.5 text-[11px] font-semibold hover:bg-slate-600 disabled:opacity-50">
              Reject
            </button>
          </div>
        </div>
      )}
      {result && !needsApproval && (
        <pre className="mt-1 max-h-48 overflow-auto text-[10px] text-slate-300">{JSON.stringify(result, null, 2).slice(0, 2500)}</pre>
      )}
      {error && <div className="mt-1 text-[11px] text-red-300">Failed: {error}</div>}
    </div>
  );
}

export default function ChatPanel() {
  const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat({ api: "/api/chat", fetch: bridgeFetch as any });
  const prompts = [
    "Check DNS and SSL for example.com",
    "Scan my Wi-Fi and find the most congested channel",
    "Show my saved Wi-Fi networks and their passwords",
    "My Wi-Fi keeps dropping — diagnose adapter power and fix it",
  ];
  return (
    <div className="flex h-full flex-col">
      <div className="flex-1 space-y-3 overflow-y-auto p-4">
        {messages.length === 0 && (
          <div className="space-y-2">
            <p className="text-sm text-slate-400">
              Ask Whitty to diagnose cloud or local issues. It chains tools automatically and asks for approval before anything that changes your PC.
            </p>
            <div className="flex flex-wrap gap-2">
              {prompts.map((p) => (
                <button key={p} onClick={() => handleInputChange({ target: { value: p } } as any)}
                  className="rounded-full border border-slate-700 px-3 py-1.5 text-xs text-slate-300 hover:border-sky-500 hover:text-sky-300">{p}</button>
              ))}
            </div>
          </div>
        )}
        {messages.map((m) => (
          <div key={m.id} className={`max-w-[85%] rounded-2xl px-4 py-3 text-sm ${m.role === "user" ? "ml-auto bg-sky-600" : "bg-slate-800"}`}>
            <div className="whitespace-pre-wrap">{m.content}</div>
            {m.toolInvocations?.map((t: any) => <ToolInvocation key={t.toolInvocationId} invocation={t} />)}
          </div>
        ))}
      </div>
      <form onSubmit={handleSubmit} className="flex gap-2 border-t border-slate-800 p-3">
        <input value={input} onChange={handleInputChange} placeholder="Diagnose something…"
          className="flex-1 rounded-xl border border-slate-700 bg-slate-900 px-4 py-2.5 text-sm outline-none focus:border-sky-500" />
        <button disabled={isLoading} className="rounded-xl bg-sky-600 px-5 py-2.5 text-sm font-bold hover:bg-sky-500 disabled:opacity-50">{isLoading ? "…" : "Send"}</button>
      </form>
    </div>
  );
}
