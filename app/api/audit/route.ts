import { NextResponse } from "next/server";
import { getAudit } from "@/lib/audit";
import { bridgeFetch } from "@/lib/bridge";
export const runtime = "nodejs";
export async function GET() {
  const local = await bridgeFetch("/audit").catch(() => ({ data: { entries: [] } }));
  return NextResponse.json({ cloud: getAudit(50), local: (local as any).data?.entries || [] });
}
