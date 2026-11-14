import { NextRequest, NextResponse } from "next/server";
import { generateWireGuardKeys, buildClientConfig } from "@/lib/vpn";
import QRCode from "qrcode";
export const runtime = "nodejs";
export async function POST(req: NextRequest) {
  const { endpoint, clientIp, dns } = await req.json();
  if (!endpoint) return NextResponse.json({ error: "endpoint required (e.g. 203.0.113.10:51820)" }, { status: 400 });
  const client = generateWireGuardKeys();
  const server = generateWireGuardKeys();
  const config = buildClientConfig({
    privateKey: client.privateKey, address: clientIp || "10.8.0.2/32",
    serverPublicKey: server.publicKey, endpoint, dns: dns || "1.1.1.1",
  });
  const qr = await QRCode.toDataURL(config);
  return NextResponse.json({ config, qr, serverPublicKey: server.publicKey, serverPrivateKey: server.privateKey, clientPublicKey: client.publicKey });
}
