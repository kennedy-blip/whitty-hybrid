import { NextRequest, NextResponse } from "next/server";
import { auditBackend, getAudit } from "@/lib/audit";
import { bridgeFetch, bridgeUrlFromRequest } from "@/lib/bridge";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET(req: NextRequest) {
  const [cloud, local] = await Promise.all([
    getAudit(50),
    bridgeFetch("/audit", {}, bridgeUrlFromRequest(req)).catch(() => ({ data: { entries: [] } })),
  ]);
  return NextResponse.json({ backend: auditBackend, cloud, local: (local as any).data?.entries || [] });
}
