import { NextRequest, NextResponse } from "next/server";
import { checkCors } from "@/lib/cloud-tools";
export const runtime = "nodejs";
export async function POST(req: NextRequest) {
  const { url } = await req.json();
  if (!url) return NextResponse.json({ error: "url required" }, { status: 400 });
  return NextResponse.json(await checkCors(url));
}
