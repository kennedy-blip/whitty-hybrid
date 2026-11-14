import { NextResponse } from "next/server";
import { getModel, providerInfo, GROQ_BASE_URL } from "@/lib/model";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// GET /api/ai-status           -> config only (fast, no tokens)
// GET /api/ai-status?ping=1    -> also sends a 1-token request upstream and
//                                 reports the exact error if it fails.
export async function GET(req: Request) {
  const info = providerInfo();
  const groqKey = process.env.GROQ_API_KEY || "";
  const openaiKey = process.env.OPENAI_API_KEY || "";
  const model = getModel();

  const report: Record<string, any> = {
    provider: info.provider,
    model: info.model,
    baseURL: info.baseURL,
    modelReady: Boolean(model),
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
          model: info.model,
          messages: [{ role: "user", content: "ping" }],
          max_tokens: 1,
        }),
        cache: "no-store",
      });
      const body = await res.text();
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

  return NextResponse.json(report);
}
