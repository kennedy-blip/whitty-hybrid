import { NextRequest, NextResponse } from "next/server";
import { bridgeStatus, bridgeUrlFromRequest } from "@/lib/bridge";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET(req: NextRequest) {
  return NextResponse.json(await bridgeStatus(bridgeUrlFromRequest(req)));
}
