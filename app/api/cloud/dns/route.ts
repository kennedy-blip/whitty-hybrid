import { NextRequest, NextResponse } from "next/server";
import { checkDns } from "@/lib/cloud-tools";
export const runtime = "nodejs";
export async function POST(req: NextRequest) {
  const { domain } = await req.json();
  if (!domain) return NextResponse.json({ error: "domain required" }, { status: 400 });
  return NextResponse.json(await checkDns(domain));
}
