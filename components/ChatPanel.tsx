"use client";
import { useState } from "react";
import { useChat } from "@ai-sdk/react";
import { getBridgeUrl } from "@/lib/bridge-client";

// Attach the current tunnel URL so the server can reach YOUR daemon.
async function bridgeFetch(input: RequestInfo | URL, init?: RequestInit) {
  const url = getBridgeUrl();
  const headers: Record<string, string> = { "Content-Type": "application/json", ...((init?.headers as Record<string, string>) || {}) };
  if (url) headers["x-bridge-url"] = url;
  return fetch(input, { ...init, headers });
}

export default function ChatPanel() {
  const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat({ api: "/api/chat", fetch: bridgeFetch as any });
  const [quick, setQuick] = useState("");
  const prompts = [
    "Check DNS and SSL for example.com",
    "Scan my local Wi-Fi and find the most congested channel",
    "Map my local ports and check for conflicts on 3000",
    "My Wi-Fi keeps dropping — diagnose adapter power and fix it",
  ];
  return (
    <div className="flex h-full flex-col">
      <div className="flex-1 space-y-3 overflow-y-auto p-4">
        {messages.length === 0 && (
          <div className="space-y-2">
            <p className="text-sm text-slate-400">Ask Whitty to diagnose cloud or local issues. It chains tools automatically (maxSteps) and asks for approval before anything mutating.</p>
            <div className="flex flex-wrap gap-2">
              {prompts.map((p) => (
                <button key={p} onClick={() => { handleInputChange({ target: { value: p } } as any); }}
                  className="rounded-full border border-slate-700 px-3 py-1.5 text-xs text-slate-300 hover:border-sky-500 hover:text-sky-300">{p}</button>
              ))}
            </div>
          </div>
        )}
        {messages.map((m) => (
          <div key={m.id} className={`max-w-[85%] rounded-2xl px-4 py-3 text-sm ${m.role === "user" ? "ml-auto bg-sky-600" : "bg-slate-800"}`}>
            <div className="whitespace-pre-wrap">{m.content}</div>
            {m.toolInvocations?.map((t: any) => (
              <div key={t.toolInvocationId} className="mt-2 rounded-lg bg-slate-950/60 px-3 py-2 text-xs">
                <span className="font-semibold text-sky-300">🔧 {t.toolName}</span>
                {t.state === "result" ? <span className="text-emerald-300"> ✓ done</span> : <span className="text-amber-300"> ⏳ running…</span>}
                {t.state === "result" && <pre className="mt-1 max-h-40 overflow-auto text-[10px] text-slate-300">{JSON.stringify(t.result, null, 2).slice(0, 2000)}</pre>}
              </div>
            ))}
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
