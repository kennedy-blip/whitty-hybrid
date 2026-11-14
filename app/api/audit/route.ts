import { NextRequest, NextResponse } from "next/server";
import { getAudit } from "@/lib/audit";
import { bridgeFetch, bridgeUrlFromRequest } from "@/lib/bridge";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET(req: NextRequest) {
  const local = await bridgeFetch("/audit", {}, bridgeUrlFromRequest(req)).catch(() => ({ data: { entries: [] } }));
  return NextResponse.json({ cloud: getAudit(50), local: (local as any).data?.entries || [] });
}
