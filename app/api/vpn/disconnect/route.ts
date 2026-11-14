import { NextRequest, NextResponse } from "next/server";
import { bridgeExecute, bridgeUrlFromRequest } from "@/lib/bridge";
import { logAudit } from "@/lib/audit";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function POST(req: NextRequest) {
  const res = await bridgeExecute("vpn_disconnect", { approved: true }, bridgeUrlFromRequest(req));
  logAudit({ tool: "vpn_disconnect", args: {}, result: res.data, approved: true, source: "vpn" });
  return NextResponse.json(res.data);
}
