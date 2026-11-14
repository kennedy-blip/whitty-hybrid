// Cloud-side audit trail.
//
// Primary store: Supabase/Postgres (survives deploys, shared across serverless
// instances). Fallback: a per-instance ring buffer so the UI still works before
// the table exists or if the DB is unreachable.
//
// The daemon keeps the authoritative local trail in SQLite (daemon/audit.db).

export type AuditEntry = {
  id: string;
  ts: string;
  tool: string;
  args: any;
  result: any;
  approved: boolean | null;
  source: string;
};

const SUPABASE_URL = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY || "";
const TABLE = process.env.SUPABASE_AUDIT_TABLE || "whitty_audit";

export const auditBackend: "supabase" | "memory" = SUPABASE_URL && SUPABASE_KEY ? "supabase" : "memory";

const memory: AuditEntry[] = [];
const MAX_MEMORY = 500;

/** Keep rows small — tool results can be whole Wi-Fi scans. */
function clip(value: any, limit = 6000) {
  try {
    const json = JSON.stringify(value ?? null);
    if (json.length <= limit) return value ?? null;
    return { truncated: true, bytes: json.length, preview: json.slice(0, limit) };
  } catch {
    return { unserializable: true };
  }
}

function headers() {
  return {
    "Content-Type": "application/json",
    apikey: SUPABASE_KEY,
    Authorization: `Bearer ${SUPABASE_KEY}`,
    Prefer: "return=minimal",
  };
}

export async function logAudit(entry: Omit<AuditEntry, "id" | "ts">): Promise<AuditEntry> {
  const record: AuditEntry = {
    ...entry,
    args: clip(entry.args),
    result: clip(entry.result),
    id: Math.random().toString(36).slice(2, 10),
    ts: new Date().toISOString(),
  };

  memory.unshift(record);
  if (memory.length > MAX_MEMORY) memory.pop();

  if (auditBackend === "supabase") {
    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/${TABLE}`, {
        method: "POST",
        headers: headers(),
        body: JSON.stringify({
          tool: record.tool,
          args: record.args,
          result: record.result,
          approved: record.approved,
          source: record.source,
          client_ts: record.ts,
        }),
        cache: "no-store",
      });
      if (!res.ok) {
        console.warn("[audit] supabase insert failed", res.status, (await res.text()).slice(0, 300));
      }
    } catch (err: any) {
      console.warn("[audit] supabase insert error", err?.message || err);
    }
  }

  return record;
}

export async function getAudit(limit = 100): Promise<AuditEntry[]> {
  if (auditBackend === "supabase") {
    try {
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/${TABLE}?select=id,ts,tool,args,result,approved,source&order=ts.desc&limit=${limit}`,
        { headers: headers(), cache: "no-store" },
      );
      if (res.ok) {
        const rows = (await res.json()) as any[];
        if (Array.isArray(rows)) {
          return rows.map((r) => ({
            id: String(r.id),
            ts: r.ts,
            tool: r.tool,
            args: r.args,
            result: r.result,
            approved: r.approved,
            source: r.source ?? "cloud",
          }));
        }
      } else {
        console.warn("[audit] supabase select failed", res.status);
      }
    } catch (err: any) {
      console.warn("[audit] supabase select error", err?.message || err);
    }
  }
  return memory.slice(0, limit);
}

export function getAuditMemory(limit = 100) {
  return memory.slice(0, limit);
}
