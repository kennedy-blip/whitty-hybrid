import { createOpenAI } from "@ai-sdk/openai";

/**
 * Model selection.
 *
 * Groq exposes an OpenAI-compatible API, so the same AI SDK provider works —
 * we only swap the base URL, the key and the default model name.
 *
 * Priority: GROQ_API_KEY  →  OPENAI_API_KEY  →  demo mode (null).
 * Override the model with AI_MODEL / GROQ_MODEL / OPENAI_MODEL.
 *
 * Groq retires model ids without warning (llama-3.3-70b-versatile started
 * answering 404 model_not_found), which used to kill the chat silently. So the
 * configured id is only a *preference*: resolveModel() probes it once per warm
 * instance and falls back through the list below if the account cannot use it.
 */
export const GROQ_BASE_URL = process.env.GROQ_BASE_URL || "https://api.groq.com/openai/v1";

// Newest/best first. Kept as ids, not display names, because that is what the
// API wants. Override the whole chain with GROQ_MODEL_FALLBACKS (comma list).
export const GROQ_FALLBACKS = (process.env.GROQ_MODEL_FALLBACKS ||
  "openai/gpt-oss-120b,openai/gpt-oss-20b,qwen/qwen3.8-27b,llama-3.3-70b-versatile,llama-3.1-8b-instant")
  .split(",")
  .map((m) => m.trim())
  .filter(Boolean);

export const GROQ_DEFAULT_MODEL = process.env.GROQ_MODEL || GROQ_FALLBACKS[0];
export const OPENAI_DEFAULT_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";

export function providerInfo() {
  if (process.env.GROQ_API_KEY) {
    return {
      provider: "groq" as const,
      model: process.env.AI_MODEL || GROQ_DEFAULT_MODEL,
      baseURL: GROQ_BASE_URL,
    };
  }
  if (process.env.OPENAI_API_KEY) {
    return {
      provider: "openai" as const,
      model: process.env.AI_MODEL || OPENAI_DEFAULT_MODEL,
      baseURL: process.env.OPENAI_BASE_URL || undefined,
    };
  }
  return { provider: "none" as const, model: null as string | null, baseURL: undefined as string | undefined };
}

function buildModel(provider: "groq" | "openai", id: string) {
  if (provider === "groq") {
    const groq = createOpenAI({ apiKey: process.env.GROQ_API_KEY!, baseURL: GROQ_BASE_URL });
    return groq(id);
  }
  const openai = createOpenAI({
    apiKey: process.env.OPENAI_API_KEY!,
    ...(process.env.OPENAI_BASE_URL ? { baseURL: process.env.OPENAI_BASE_URL } : {}),
  });
  return openai(id);
}

/** Cheap "can this account actually use this id" check. */
async function probeGroq(id: string): Promise<{ ok: boolean; detail?: string }> {
  const key = process.env.GROQ_API_KEY || "";
  if (!key) return { ok: false, detail: "no GROQ_API_KEY" };
  try {
    const res = await fetch(`${GROQ_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({ model: id, messages: [{ role: "user", content: "hi" }], max_tokens: 1 }),
      cache: "no-store",
    });
    if (res.ok) return { ok: true };
    const body = await res.text();
    return { ok: false, detail: `${res.status} ${body.slice(0, 200)}` };
  } catch (err: any) {
    return { ok: false, detail: String(err?.message || err) };
  }
}

type Resolved = {
  provider: "groq" | "openai";
  id: string;
  model: ReturnType<typeof buildModel>;
  tried: { id: string; ok: boolean; detail?: string }[];
  at: number;
  source: "probe" | "cache";
};

let cache: Resolved | null = null;
const TTL_MS = 10 * 60 * 1000;

/** The model to actually stream with, or null in demo mode. */
export async function resolveModel(force = false): Promise<Resolved | null> {
  const info = providerInfo();
  if (info.provider === "none" || !info.model) return null;

  if (!force && cache && Date.now() - cache.at < TTL_MS) {
    return { ...cache, source: "cache" };
  }

  if (info.provider === "openai") {
    // OpenAI keeps ids stable; trust the configured one.
    cache = { provider: "openai", id: info.model, model: buildModel("openai", info.model), tried: [], at: Date.now(), source: "probe" };
    return cache;
  }

  const candidates = Array.from(new Set([info.model, ...GROQ_FALLBACKS]));
  const tried: { id: string; ok: boolean; detail?: string }[] = [];
  for (const id of candidates) {
    const result = await probeGroq(id);
    tried.push({ id, ...result });
    if (result.ok) {
      cache = { provider: "groq", id, model: buildModel("groq", id), tried, at: Date.now(), source: "probe" };
      if (id !== info.model) {
        console.warn(`[model] configured "${info.model}" unusable, falling back to "${id}"`);
      }
      return cache;
    }
  }

  // Nothing worked: remember the failure briefly so we don't hammer the API.
  cache = null;
  lastFailure = { tried, at: Date.now() };
  return null;
}

let lastFailure: { tried: { id: string; ok: boolean; detail?: string }[]; at: number } | null = null;
export function modelFailure() {
  return lastFailure;
}

/** Synchronous helper kept for callers that only need "is AI configured". */
export function getModel() {
  const info = providerInfo();
  if (info.provider === "none" || !info.model) return null;
  return buildModel(info.provider, info.model);
}
