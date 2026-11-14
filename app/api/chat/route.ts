import { streamText, tool } from "ai";
import { openai } from "@ai-sdk/openai";
import { z } from "zod";
import { checkDns, checkSsl, checkCors, checkApiHealth } from "@/lib/cloud-tools";
import { bridgeExecute, bridgeUrlFromRequest } from "@/lib/bridge";
import { logAudit } from "@/lib/audit";

export const runtime = "nodejs";
export const maxDuration = 60;

const MUTATING = new Set(["disable_adapter_sleep", "kill_process", "network_recovery", "vpn_connect", "vpn_disconnect", "vpn_kill_switch"]);

// Local tools proxy through the daemon. Mutating ones are gated: the daemon
// returns requiresApproval and the UI renders an Approve/Reject card.
async function localTool(name: string, args: any, base?: string) {
  const res = await bridgeExecute(name, args, base);
  logAudit({ tool: name, args, result: res.data, approved: null, source: "ai" });
  return res.data;
}

export async function POST(req: Request) {
  const { messages } = await req.json();
  const bridgeBase = bridgeUrlFromRequest(req);
  if (!process.env.OPENAI_API_KEY) {
    // Demo mode: no AI key — stream a helpful guide instead of failing.
    const stream = new ReadableStream({
      start(c) {
        const text = "Demo mode: set OPENAI_API_KEY on Vercel to enable the AI agent. Meanwhile, use the Cloud Sentinel + Local Bridge + VPN panels on the left — they all work without AI. The daemon status shows whether your PC bridge is connected.";
        c.enqueue(new TextEncoder().encode(`0:${JSON.stringify(text)}\n`));
        c.close();
      },
    });
    return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  const result = streamText({
    model: openai(process.env.AI_MODEL || "gpt-4o-mini"),
    system: `You are Whitty, a hybrid diagnostic agent. You have CLOUD tools (DNS, SSL, CORS, API health) that run instantly, and LOCAL tools (Wi-Fi scan, ports, power-state, network recovery, VPN) that run on the user's PC via a bridge daemon. Chain tools with maxSteps to fully diagnose. Read-only tools are auto-approved. Mutating tools (disable sleep, kill process, network recovery, VPN connect/disconnect) will trigger a human approval card — explain to the user that approval is needed before they run. Always summarize findings with clear next steps.`,
    messages,
    maxSteps: 6,
    tools: {
      check_dns: tool({ description: "Query A/CNAME/MX/TXT records for a domain", parameters: z.object({ domain: z.string() }), execute: async ({ domain }) => checkDns(domain) }),
      check_ssl: tool({ description: "Audit TLS certificate for a domain", parameters: z.object({ domain: z.string() }), execute: async ({ domain }) => checkSsl(domain) }),
      check_cors: tool({ description: "Analyze CORS + security headers for a URL", parameters: z.object({ url: z.string() }), execute: async ({ url }) => checkCors(url) }),
      check_api_health: tool({ description: "Latency triage for an API URL (3 samples)", parameters: z.object({ url: z.string() }), execute: async ({ url }) => checkApiHealth(url) }),
      scan_wifi: tool({ description: "Scan local Wi-Fi: SSIDs, BSSIDs, RSSI, channels, congestion", parameters: z.object({}), execute: async () => localTool("scan_wifi", {}, bridgeBase) }),
      adapter_power_status: tool({ description: "Check wireless adapter power-saving state", parameters: z.object({}), execute: async () => localTool("adapter_power_status", {}, bridgeBase) }),
      list_ports: tool({ description: "Map TCP/UDP ports to PIDs and process paths", parameters: z.object({}), execute: async () => localTool("list_ports", {}, bridgeBase) }),
      system_overview: tool({ description: "CPU/memory/disk/interfaces/IPs of the local PC", parameters: z.object({}), execute: async () => localTool("system_overview", {}, bridgeBase) }),
      disable_adapter_sleep: tool({ description: "MUTATING — disable aggressive adapter power saving (needs approval)", parameters: z.object({}), execute: async () => localTool("disable_adapter_sleep", {}, bridgeBase) }),
      kill_process: tool({ description: "MUTATING — kill a process by PID (needs approval)", parameters: z.object({ pid: z.number() }), execute: async ({ pid }) => localTool("kill_process", { pid }, bridgeBase) }),
      network_recovery: tool({ description: "MUTATING — flush DNS / renew DHCP / reset Winsock (needs approval)", parameters: z.object({ action: z.enum(["flush_dns", "renew_dhcp", "reset_winsock", "reset_tcpip"]) }), execute: async ({ action }) => localTool("network_recovery", { action }, bridgeBase) }),
      vpn_status: tool({ description: "Check WireGuard VPN status on the local PC", parameters: z.object({}), execute: async () => localTool("vpn_status", {}, bridgeBase) }),
      vpn_connect: tool({ description: "MUTATING — one-click connect the WireGuard VPN on the local PC (needs approval)", parameters: z.object({}), execute: async () => localTool("vpn_connect", {}, bridgeBase) }),
      vpn_disconnect: tool({ description: "MUTATING — disconnect the WireGuard VPN (needs approval)", parameters: z.object({}), execute: async () => localTool("vpn_disconnect", {}, bridgeBase) }),
    },
  });
  return result.toDataStreamResponse();
}
