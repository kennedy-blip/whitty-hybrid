import { NextRequest, NextResponse } from "next/server";
import { bridgeExecute, bridgeUrlFromRequest } from "@/lib/bridge";
import { logAudit } from "@/lib/audit";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function POST(req: NextRequest) {
  const { tool, args, approved } = await req.json();
  const res = await bridgeExecute(tool, args || {}, bridgeUrlFromRequest(req), approved === true);
  await logAudit({ tool, args: args || {}, result: res.data, approved: approved ?? null, source: "bridge" });
  return NextResponse.json(res.data);
}
