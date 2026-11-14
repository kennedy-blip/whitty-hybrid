import { NextRequest, NextResponse } from "next/server";
import { bridgeExecute, bridgeUrlFromRequest } from "@/lib/bridge";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET(req: NextRequest) {
  const res = await bridgeExecute("vpn_status", {}, bridgeUrlFromRequest(req));
  return NextResponse.json(res.data);
}
