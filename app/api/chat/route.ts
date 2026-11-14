import { streamText } from "ai";
import { bridgeUrlFromRequest } from "@/lib/bridge";
import { buildAgentTools } from "@/lib/agent-tools";
import { resolveModel, modelFailure, providerInfo } from "@/lib/model";

export const runtime = "nodejs";
export const maxDuration = 60;

export async function POST(req: Request) {
  try {
    return await handle(req);
  } catch (err: any) {
    console.error("[chat] fatal", err);
    const message = `The chat backend failed: ${err?.message || String(err)}`;
    const stream = new ReadableStream({
      start(c) {
        c.enqueue(new TextEncoder().encode(`0:${JSON.stringify(message)}\n`));
        c.close();
      },
    });
    return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
}

async function handle(req: Request) {
  const { messages } = await req.json();
  const bridgeBase = bridgeUrlFromRequest(req);
  const resolved = await resolveModel();
  const model = resolved?.model ?? null;

  if (!model && providerInfo().provider !== "none") {
    // A key exists but no model id works for this account. Say so, loudly.
    const tried = (modelFailure()?.tried || []).map((t) => `${t.id} -> ${t.detail || "failed"}`).join("\n");
    const text =
      `The AI key is configured but no usable model was found for it.\n\nTried:\n${tried}\n\n` +
      `Fix: set GROQ_MODEL in Vercel to a model your account can use ` +
      `(open /api/ai-status?models=1 on this site to list the ids your key can use).`;
    const stream = new ReadableStream({
      start(c) {
        c.enqueue(new TextEncoder().encode(`0:${JSON.stringify(text)}\n`));
        c.close();
      },
    });
    return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }

  if (!model) {
    // Demo mode: no AI key configured — stream guidance instead of failing.
    const text =
      "Demo mode: no AI key is configured. Add GROQ_API_KEY (or OPENAI_API_KEY) in Vercel → Settings → Environment Variables and redeploy to wake the agent. Every panel on the left works without AI — Cloud Sentinel, Local Bridge and the One-Click VPN.";
    const stream = new ReadableStream({
      start(c) {
        c.enqueue(new TextEncoder().encode(`0:${JSON.stringify(text)}\n`));
        c.close();
      },
    });
    return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }

  const info = providerInfo();
  console.log(`[chat] provider=${info.provider} model=${resolved?.id} (${resolved?.source})`);

  const result = streamText({
    model,
    system: `You are Whitty, a hybrid diagnostic agent running on ${info.provider} (${resolved?.id || info.model}).
You have CLOUD tools (DNS, SSL, CORS, API health) that run instantly on Vercel, and LOCAL tools (Wi-Fi scan, saved Wi-Fi passwords, ports, power-state, network recovery, VPN) that run on the user's own PC through a bridge daemon.

Tool-chaining: chain multiple tools in one turn to reach a real diagnosis (maxSteps 6). Always finish with a short summary and concrete next steps.

Safety: read-only tools run automatically. Mutating tools — disable_adapter_sleep, kill_process, network_recovery, vpn_connect, vpn_disconnect, wifi_saved_passwords, wifi_profile_details — are blocked by the daemon until the human approves. When one of those returns {requiresApproval: true}, tell the user you need their approval and that an Approve button has appeared; do NOT claim the action ran.

Wi-Fi passwords: use wifi_saved_passwords only when the user explicitly asks to see saved networks' passwords. It requires approval.
Sign-in networks: if the user says "the network asks me to sign in" or "it needs a login", call captive_portal_status (read-only) and tell them the portal URL. For corporate/802.1X networks use wifi_profile_details to show the EAP method and stored identity — explain that the password lives in the identity provider, not in Windows, so it cannot be extracted.`,
    messages,
    maxSteps: 6,
    tools: buildAgentTools(bridgeBase),
  });

  return result.toDataStreamResponse({
    getErrorMessage: (error) => {
      const e = error as any;
      const parts = [e?.message || String(error)];
      if (e?.cause?.message) parts.push(`cause: ${e.cause.message}`);
      if (e?.responseBody) parts.push(`body: ${String(e.responseBody).slice(0, 300)}`);
      console.error("[chat] stream error", parts.join(" | "));
      return parts.join(" | ");
    },
  });
}
