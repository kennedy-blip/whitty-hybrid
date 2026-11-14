import { NextResponse } from "next/server";
import { bridgeStatus } from "@/lib/bridge";
export const runtime = "nodejs";
export async function GET() { return NextResponse.json(await bridgeStatus()); }
