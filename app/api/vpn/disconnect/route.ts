import { NextResponse } from "next/server";
import { bridgeExecute } from "@/lib/bridge";
import { logAudit } from "@/lib/audit";
export const runtime = "nodejs";
export async function POST() {
  const res = await bridgeExecute("vpn_disconnect", { approved: true });
  logAudit({ tool: "vpn_disconnect", args: {}, result: res.data, approved: true, source: "vpn" });
  return NextResponse.json(res.data);
}
