import crypto from "crypto";

// WireGuard X25519 key generation using Node's built-in crypto.
export function generateWireGuardKeys() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync("x25519");
  const privJwk = privateKey.export({ format: "jwk" }) as any;
  const pubJwk = publicKey.export({ format: "jwk" }) as any;
  const b64urlToB64 = (s: string) => s.replace(/-/g, "+").replace(/_/g, "/").padEnd(44, "=");
  return {
    privateKey: Buffer.from(b64urlToB64(privJwk.x), "base64").toString("base64"),
    publicKey: Buffer.from(b64urlToB64(pubJwk.x), "base64").toString("base64"),
  };
}

export function buildClientConfig(opts: {
  privateKey: string; address: string; serverPublicKey: string; endpoint: string; dns?: string; allowedIps?: string; keepalive?: number;
}) {
  return `[Interface]
PrivateKey = ${opts.privateKey}
Address = ${opts.address}
DNS = ${opts.dns || "1.1.1.1"}

[Peer]
PublicKey = ${opts.serverPublicKey}
Endpoint = ${opts.endpoint}
AllowedIPs = ${opts.allowedIps || "0.0.0.0/0, ::/0"}
PersistentKeepalive = ${opts.keepalive || 25}
`;
}

export function buildServerConfig(opts: { privateKey: string; address: string; listenPort?: number; peers: { publicKey: string; allowedIps: string }[] }) {
  const peers = opts.peers.map((p) => `\n[Peer]\nPublicKey = ${p.publicKey}\nAllowedIPs = ${p.allowedIps}\n`).join("\n");
  return `[Interface]
PrivateKey = ${opts.privateKey}
Address = ${opts.address}
ListenPort = ${opts.listenPort || 51820}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
${peers}`;
}
