import { NextRequest, NextResponse } from "next/server";
import { bridgeExecute, bridgeUrlFromRequest } from "@/lib/bridge";
import { logAudit } from "@/lib/audit";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function POST(req: NextRequest) {
  const base = bridgeUrlFromRequest(req);
  const body = await req.json().catch(() => ({}));
  // If a config is supplied, apply it first (exit-node mode), then connect.
  if (body.config) {
    const applied = await bridgeExecute("vpn_apply_config", { config: body.config }, base, true);
    logAudit({ tool: "vpn_apply_config", args: {}, result: applied.data, approved: true, source: "vpn" });
    return NextResponse.json(applied.data);
  }
  const res = await bridgeExecute("vpn_connect", {}, base, true);
  logAudit({ tool: "vpn_connect", args: {}, result: res.data, approved: true, source: "vpn" });
  return NextResponse.json(res.data);
}
