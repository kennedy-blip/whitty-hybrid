import { streamText, tool } from "ai";
import { z } from "zod";
import { checkDns, checkSsl, checkCors, checkApiHealth } from "@/lib/cloud-tools";
import { bridgeExecute, bridgeUrlFromRequest } from "@/lib/bridge";
import { getModel, providerInfo } from "@/lib/model";
import { logAudit } from "@/lib/audit";

export const runtime = "nodejs";
export const maxDuration = 60;

// Local tools run on the user's PC through the daemon. Read-only ones execute
// immediately; mutating ones are stopped by the daemon's gate and the payload
// (requiresApproval) is surfaced to the UI as an Approve / Reject card.
async function localTool(name: string, args: Record<string, any>, base?: string) {
  const res = await bridgeExecute(name, args, base);
  logAudit({ tool: name, args, result: res.data, approved: null, source: "ai" });
  return res.data;
}

export async function POST(req: Request) {
  const { messages } = await req.json();
  const bridgeBase = bridgeUrlFromRequest(req);
  const model = getModel();

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

  const result = streamText({
    model,
    system: `You are Whitty, a hybrid diagnostic agent running on ${info.provider} (${info.model}).
You have CLOUD tools (DNS, SSL, CORS, API health) that run instantly on Vercel, and LOCAL tools (Wi-Fi scan, saved Wi-Fi passwords, ports, power-state, network recovery, VPN) that run on the user's own PC through a bridge daemon.

Tool-chaining: chain multiple tools in one turn to reach a real diagnosis (maxSteps 6). Always finish with a short summary and concrete next steps.

Safety: read-only tools run automatically. Mutating tools — disable_adapter_sleep, kill_process, network_recovery, vpn_connect, vpn_disconnect, wifi_saved_passwords — are blocked by the daemon until the human approves. When one of those returns {requiresApproval: true}, tell the user you need their approval and that an Approve button has appeared; do NOT claim the action ran.

Wi-Fi passwords: use wifi_saved_passwords only when the user explicitly asks to see saved networks' passwords. It requires approval.`,
    messages,
    maxSteps: 6,
    tools: {
      check_dns: tool({ description: "Query A/CNAME/MX/TXT records for a domain", parameters: z.object({ domain: z.string() }), execute: async ({ domain }) => checkDns(domain) }),
      check_ssl: tool({ description: "Audit the TLS certificate for a domain", parameters: z.object({ domain: z.string() }), execute: async ({ domain }) => checkSsl(domain) }),
      check_cors: tool({ description: "Analyze CORS + security headers for a URL", parameters: z.object({ url: z.string() }), execute: async ({ url }) => checkCors(url) }),
      check_api_health: tool({ description: "Latency triage for an API URL (3 samples)", parameters: z.object({ url: z.string() }), execute: async ({ url }) => checkApiHealth(url) }),

      scan_wifi: tool({ description: "Scan nearby Wi-Fi: SSIDs, BSSIDs, RSSI, channels, congestion, channel advice", parameters: z.object({}), execute: async () => localTool("scan_wifi", {}, bridgeBase) }),
      wifi_saved_passwords: tool({ description: "MUTATING (needs approval) — list saved Wi-Fi profiles with their stored passwords from this PC", parameters: z.object({}), execute: async () => localTool("wifi_saved_passwords", {}, bridgeBase) }),
      adapter_power_status: tool({ description: "Check whether the wireless adapter uses aggressive power saving", parameters: z.object({}), execute: async () => localTool("adapter_power_status", {}, bridgeBase) }),
      list_ports: tool({ description: "Map TCP/UDP ports to PIDs and process paths", parameters: z.object({}), execute: async () => localTool("list_ports", {}, bridgeBase) }),
      system_overview: tool({ description: "CPU/memory/disk/interfaces/IPs of the local PC", parameters: z.object({}), execute: async () => localTool("system_overview", {}, bridgeBase) }),

      disable_adapter_sleep: tool({ description: "MUTATING (needs approval) — disable aggressive adapter power saving", parameters: z.object({}), execute: async () => localTool("disable_adapter_sleep", {}, bridgeBase) }),
      kill_process: tool({ description: "MUTATING (needs approval) — kill a process by PID", parameters: z.object({ pid: z.number() }), execute: async ({ pid }) => localTool("kill_process", { pid }, bridgeBase) }),
      network_recovery: tool({ description: "MUTATING (needs approval) — flush DNS / renew DHCP / reset Winsock / reset TCP-IP", parameters: z.object({ action: z.enum(["flush_dns", "renew_dhcp", "reset_winsock", "reset_tcpip"]) }), execute: async ({ action }) => localTool("network_recovery", { action }, bridgeBase) }),

      vpn_status: tool({ description: "Check WireGuard VPN status on the local PC", parameters: z.object({}), execute: async () => localTool("vpn_status", {}, bridgeBase) }),
      vpn_connect: tool({ description: "MUTATING (needs approval) — bring the WireGuard VPN up on the local PC", parameters: z.object({}), execute: async () => localTool("vpn_connect", {}, bridgeBase) }),
      vpn_disconnect: tool({ description: "MUTATING (needs approval) — bring the WireGuard VPN down", parameters: z.object({}), execute: async () => localTool("vpn_disconnect", {}, bridgeBase) }),
    },
  });

  return result.toDataStreamResponse();
}
