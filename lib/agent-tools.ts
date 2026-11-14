import { tool } from "ai";
import { z } from "zod";
import { checkDns, checkSsl, checkCors, checkApiHealth } from "@/lib/cloud-tools";
import { bridgeExecute } from "@/lib/bridge";
import { logAudit } from "@/lib/audit";

/** Run a tool on the user's PC through the tunnel and record it in the audit trail. */
export async function localTool(name: string, args: Record<string, any>, base?: string) {
  const res = await bridgeExecute(name, args, base);
  await logAudit({ tool: name, args, result: res.data, approved: null, source: "ai" });
  return res.data;
}

/**
 * The full tool set. Shared by the chat route and /api/ai-status?tools=1.
 *
 * SCHEMA RULE (learned the hard way): Groq validates each tool schema and
 * rejects the whole request with
 *   "invalid JSON schema ... /required: `required` is required to be supplied
 *    and to be an array including every key in properties"
 * when an object has properties but no `required` array — which is exactly what
 * z.object({ ssid: z.string().optional() }) converts to. So every property is
 * required here and optionality is expressed with a default value ("") plus a
 * description instead of z.optional().
 */
export function buildAgentTools(bridgeBase?: string) {
  return {
    // ---- cloud (runs on Vercel) ----
    check_dns: tool({
      description: "Query A/CNAME/MX/TXT records for a domain",
      parameters: z.object({ domain: z.string() }),
      execute: async ({ domain }) => checkDns(domain),
    }),
    check_ssl: tool({
      description: "Audit the TLS certificate for a domain",
      parameters: z.object({ domain: z.string() }),
      execute: async ({ domain }) => checkSsl(domain),
    }),
    check_cors: tool({
      description: "Analyze CORS + security headers for a URL",
      parameters: z.object({ url: z.string() }),
      execute: async ({ url }) => checkCors(url),
    }),
    check_api_health: tool({
      description: "Latency triage for an API URL (3 samples)",
      parameters: z.object({ url: z.string() }),
      execute: async ({ url }) => checkApiHealth(url),
    }),

    // ---- local: read-only (runs on the user's PC) ----
    scan_wifi: tool({
      description: "Scan nearby Wi-Fi: SSIDs, BSSIDs, RSSI, channels, congestion, channel advice",
      parameters: z.object({}),
      execute: async () => localTool("scan_wifi", {}, bridgeBase),
    }),
    captive_portal_status: tool({
      description: "Check whether the current Wi-Fi is stuck behind a captive-portal sign-in page and return the portal URL",
      parameters: z.object({}),
      execute: async () => localTool("captive_portal_status", {}, bridgeBase),
    }),
    adapter_power_status: tool({
      description: "Check whether the wireless adapter uses aggressive power saving",
      parameters: z.object({}),
      execute: async () => localTool("adapter_power_status", {}, bridgeBase),
    }),
    list_ports: tool({
      description: "Map TCP/UDP ports to PIDs and process paths",
      parameters: z.object({}),
      execute: async () => localTool("list_ports", {}, bridgeBase),
    }),
    system_overview: tool({
      description: "CPU/memory/disk/interfaces/IPs of the local PC",
      parameters: z.object({}),
      execute: async () => localTool("system_overview", {}, bridgeBase),
    }),
    vpn_status: tool({
      description: "Check WireGuard VPN status on the local PC",
      parameters: z.object({}),
      execute: async () => localTool("vpn_status", {}, bridgeBase),
    }),

    // ---- local: mutating (blocked until the human approves) ----
    wifi_saved_passwords: tool({
      description: "MUTATING (needs approval) — list saved Wi-Fi profiles with their stored passwords from this PC",
      parameters: z.object({}),
      execute: async () => localTool("wifi_saved_passwords", {}, bridgeBase),
    }),
    wifi_profile_details: tool({
      description:
        "MUTATING (needs approval) — deep profile for saved Wi-Fi networks: PSK, 802.1X/EAP method, stored identity, whether the network needs a sign-in page. Pass an SSID, or an empty string to inspect every saved network.",
      parameters: z.object({
        ssid: z
          .string()
          .describe("SSID to inspect, or an empty string \"\" to inspect every saved network"),
      }),
      execute: async ({ ssid }) => localTool("wifi_profile_details", ssid ? { ssid } : {}, bridgeBase),
    }),
    disable_adapter_sleep: tool({
      description: "MUTATING (needs approval) — disable aggressive adapter power saving",
      parameters: z.object({}),
      execute: async () => localTool("disable_adapter_sleep", {}, bridgeBase),
    }),
    kill_process: tool({
      description: "MUTATING (needs approval) — kill a process by PID",
      parameters: z.object({ pid: z.number() }),
      execute: async ({ pid }) => localTool("kill_process", { pid }, bridgeBase),
    }),
    network_recovery: tool({
      description: "MUTATING (needs approval) — flush DNS / renew DHCP / reset Winsock / reset TCP-IP",
      parameters: z.object({ action: z.enum(["flush_dns", "renew_dhcp", "reset_winsock", "reset_tcpip"]) }),
      execute: async ({ action }) => localTool("network_recovery", { action }, bridgeBase),
    }),
    vpn_connect: tool({
      description: "MUTATING (needs approval) — bring the WireGuard VPN up on the local PC",
      parameters: z.object({}),
      execute: async () => localTool("vpn_connect", {}, bridgeBase),
    }),
    vpn_disconnect: tool({
      description: "MUTATING (needs approval) — bring the WireGuard VPN down",
      parameters: z.object({}),
      execute: async () => localTool("vpn_disconnect", {}, bridgeBase),
    }),
  };
}
