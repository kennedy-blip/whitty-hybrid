import { createOpenAI } from "@ai-sdk/openai";

/**
 * Model selection.
 *
 * Groq exposes an OpenAI-compatible API, so the same AI SDK provider works —
 * we only swap the base URL, the key and the default model name.
 *
 * Priority: GROQ_API_KEY  →  OPENAI_API_KEY  →  demo mode (null).
 * Override the model with AI_MODEL / GROQ_MODEL / OPENAI_MODEL.
 */
export const GROQ_BASE_URL = process.env.GROQ_BASE_URL || "https://api.groq.com/openai/v1";
export const GROQ_DEFAULT_MODEL = process.env.GROQ_MODEL || "llama-3.3-70b-versatile";
export const OPENAI_DEFAULT_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";

export function providerInfo() {
  if (process.env.GROQ_API_KEY) {
    return { provider: "groq" as const, model: process.env.AI_MODEL || GROQ_DEFAULT_MODEL, baseURL: GROQ_BASE_URL };
  }
  if (process.env.OPENAI_API_KEY) {
    return {
      provider: "openai" as const,
      model: process.env.AI_MODEL || OPENAI_DEFAULT_MODEL,
      baseURL: process.env.OPENAI_BASE_URL || undefined,
    };
  }
  return { provider: "none" as const, model: null, baseURL: undefined };
}

export function getModel() {
  const info = providerInfo();
  if (info.provider === "groq") {
    const groq = createOpenAI({ apiKey: process.env.GROQ_API_KEY!, baseURL: info.baseURL });
    return groq(info.model as string);
  }
  if (info.provider === "openai") {
    const openaiProvider = createOpenAI({
      apiKey: process.env.OPENAI_API_KEY!,
      ...(info.baseURL ? { baseURL: info.baseURL } : {}),
    });
    return openaiProvider(info.model as string);
  }
  return null;
}
