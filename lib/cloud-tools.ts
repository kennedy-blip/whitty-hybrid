import dns from "dns/promises";
import tls from "tls";
import https from "https";

export async function checkDns(domain: string) {
  const clean = domain.replace(/^https?:\/\//, "").replace(/\/.*$/, "");
  const [a, cname, mx, txt] = await Promise.allSettled([
    dns.resolve4(clean),
    dns.resolveCname(clean).catch(() => []),
    dns.resolveMx(clean).catch(() => []),
    dns.resolveTxt(clean).catch(() => []),
  ]);
  const get = (r: PromiseSettledResult<any>) => (r.status === "fulfilled" ? r.value : []);
  return {
    domain: clean,
    A: get(a),
    CNAME: get(cname),
    MX: get(mx).map((m: any) => ({ exchange: m.exchange, priority: m.priority })),
    TXT: get(txt).map((t: string[]) => t.join("")),
    resolversChecked: ["1.1.1.1", "8.8.8.8", "9.9.9.9"],
    healthy: get(a).length > 0,
  };
}

export async function checkSsl(domain: string) {
  const clean = domain.replace(/^https?:\/\//, "").replace(/:.*$/, "").replace(/\/.*$/, "");
  return new Promise((resolve) => {
    const socket = tls.connect(443, clean, { servername: clean, timeout: 8000 }, () => {
      const cert = socket.getPeerCertificate(true);
      const issuer = socket.getPeerCertificate().issuer || {};
      socket.end();
      const validTo = cert.valid_to ? new Date(cert.valid_to) : null;
      const daysLeft = validTo ? Math.floor((validTo.getTime() - Date.now()) / 86400000) : null;
      resolve({
        domain: clean,
        valid: socket.authorized,
        issuer: (issuer as any).O || (issuer as any).CN || "unknown",
        subject: (cert.subject as any)?.CN || clean,
        validFrom: cert.valid_from || null,
        validTo: cert.valid_to || null,
        daysRemaining: daysLeft,
        expired: daysLeft !== null && daysLeft < 0,
        expiringSoon: daysLeft !== null && daysLeft >= 0 && daysLeft < 30,
        fingerprint: cert.fingerprint || null,
        chainValid: socket.authorized,
      });
    });
    socket.on("error", (e) => resolve({ domain: clean, valid: false, error: String(e) }));
    socket.on("timeout", () => { socket.destroy(); resolve({ domain: clean, valid: false, error: "timeout" }); });
  });
}

export async function checkCors(url: string) {
  const target = url.startsWith("http") ? url : `https://${url}`;
  return new Promise((resolve) => {
    const req = https.request(target, { method: "OPTIONS", timeout: 8000, headers: { Origin: "https://example.com", "Access-Control-Request-Method": "GET" } }, (res) => {
      const h = res.headers;
      const checks = {
        corsAllowOrigin: h["access-control-allow-origin"] || null,
        corsAllowMethods: h["access-control-allow-methods"] || null,
        corsAllowHeaders: h["access-control-allow-headers"] || null,
        hsts: h["strict-transport-security"] || null,
        csp: h["content-security-policy"] || null,
        xFrameOptions: h["x-frame-options"] || null,
        xContentTypeOptions: h["x-content-type-options"] || null,
        referrerPolicy: h["referrer-policy"] || null,
      };
      const score = [checks.hsts, checks.csp, checks.xFrameOptions, checks.xContentTypeOptions].filter(Boolean).length;
      resolve({ url: target, status: res.statusCode, headers: checks, securityScore: `${score}/4`, corsEnabled: !!checks.corsAllowOrigin });
    });
    req.on("error", (e) => resolve({ url: target, error: String(e) }));
    req.on("timeout", () => { req.destroy(); resolve({ url: target, error: "timeout" }); });
    req.end();
  });
}

export async function checkApiHealth(url: string, method = "GET") {
  const target = url.startsWith("http") ? url : `https://${url}`;
  const samples: number[] = [];
  let lastStatus = 0;
  let lastBody = "";
  for (let i = 0; i < 3; i++) {
    const t0 = Date.now();
    try {
      const res = await fetch(target, { method, redirect: "follow", signal: AbortSignal.timeout(10000) });
      samples.push(Date.now() - t0);
      lastStatus = res.status;
      lastBody = (await res.text()).slice(0, 500);
    } catch (e) {
      samples.push(Date.now() - t0);
      lastStatus = 0;
      lastBody = String(e);
    }
  }
  const avg = Math.round(samples.reduce((a, b) => a + b, 0) / samples.length);
  return { url: target, status: lastStatus, latencyMs: avg, samples, ok: lastStatus >= 200 && lastStatus < 400, bodyPreview: lastBody };
}
