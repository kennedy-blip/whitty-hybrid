import { NextResponse } from "next/server";
import { resolveModel, providerInfo, GROQ_BASE_URL, GROQ_FALLBACKS } from "@/lib/model";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// GET /api/ai-status           -> config only (fast, no tokens)
// GET /api/ai-status?ping=1    -> also sends a 1-token request upstream and
//                                 reports the exact error if it fails.
export async function GET(req: Request) {
  const info = providerInfo();
  const groqKey = process.env.GROQ_API_KEY || "";
  const openaiKey = process.env.OPENAI_API_KEY || "";
  const resolved = await resolveModel();

  const report: Record<string, any> = {
    provider: info.provider,
    model: info.model,
    baseURL: info.baseURL,
    modelReady: Boolean(resolved),
    resolvedModel: resolved?.id ?? null,
    howResolved: resolved?.source ?? null,
    fallbackChain: GROQ_FALLBACKS,
    probe: resolved?.tried ?? [],
    keys: {
      GROQ_API_KEY: groqKey ? `set (${groqKey.slice(0, 6)}...${groqKey.slice(-4)}, ${groqKey.length} chars)` : "missing",
      OPENAI_API_KEY: openaiKey ? `set (${openaiKey.length} chars)` : "missing",
    },
  };

  const url = new URL(req.url);

  if (url.searchParams.get("models") === "1" && groqKey) {
    try {
      const res = await fetch(`${GROQ_BASE_URL}/models`, {
        headers: { Authorization: `Bearer ${groqKey}` },
        cache: "no-store",
      });
      const json: any = await res.json();
      report.availableModels = Array.isArray(json?.data) ? json.data.map((m: any) => m.id) : json;
    } catch (err: any) {
      report.availableModels = { error: String(err?.message || err) };
    }
  }

  if (url.searchParams.get("ping") === "1" && info.provider === "groq" && groqKey) {
    const started = Date.now();
    try {
      const res = await fetch(`${GROQ_BASE_URL}/chat/completions`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${groqKey}` },
        body: JSON.stringify({
          model: resolved?.id || info.model,
          messages: [{ role: "user", content: "ping" }],
          max_tokens: 1,
        }),
        cache: "no-store",
      });
      const body = await res.text();
      report.pingedModel = resolved?.id || info.model;
      report.ping = {
        ok: res.ok,
        status: res.status,
        ms: Date.now() - started,
        body: body.slice(0, 600),
      };
    } catch (err: any) {
      report.ping = { ok: false, error: String(err?.message || err), ms: Date.now() - started };
    }
  } else if (url.searchParams.get("ping") === "1") {
    report.ping = { skipped: "no Groq key configured" };
  }

  // ?selftest=1 runs one real agent turn (model + tool call + answer) so the
  // chat can be proven end-to-end without a browser.
  if (url.searchParams.get("selftest") === "1" && resolved) {
    const started = Date.now();
    try {
      const { generateText, tool } = await import("ai");
      const { z } = await import("zod");
      const { checkDns } = await import("@/lib/cloud-tools");
      const out = await generateText({
        model: resolved.model,
        maxSteps: 3,
        system: "You are a diagnostic agent. Use the tool when asked about DNS, then answer in one short sentence.",
        prompt: "Use check_dns for example.com and tell me the A record.",
        tools: {
          check_dns: tool({
            description: "Query A/CNAME/MX/TXT records for a domain",
            parameters: z.object({ domain: z.string() }),
            execute: async ({ domain }) => checkDns(domain),
          }),
        },
      });
      const calls = (out.steps || []).flatMap((st: any) => (st.toolCalls || []).map((c: any) => `${c.toolName}(${JSON.stringify(c.args)})`));
      report.selftest = {
        ok: true,
        ms: Date.now() - started,
        toolCalls: calls,
        steps: out.steps?.length ?? 0,
        text: (out.text || "").slice(0, 400),
      };
    } catch (err: any) {
      report.selftest = { ok: false, ms: Date.now() - started, error: String(err?.message || err) };
    }
  }

  return NextResponse.json(report);
}
