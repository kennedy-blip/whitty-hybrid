import { NextResponse } from "next/server";
import { bridgeExecute } from "@/lib/bridge";
export const runtime = "nodejs";
export async function GET() {
  const res = await bridgeExecute("vpn_status");
  return NextResponse.json(res.data);
}
