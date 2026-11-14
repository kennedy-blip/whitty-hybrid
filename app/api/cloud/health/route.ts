import { NextRequest, NextResponse } from "next/server";
import { checkApiHealth } from "@/lib/cloud-tools";
export const runtime = "nodejs";
export async function POST(req: NextRequest) {
  const { url, method } = await req.json();
  if (!url) return NextResponse.json({ error: "url required" }, { status: 400 });
  return NextResponse.json(await checkApiHealth(url, method || "GET"));
}
