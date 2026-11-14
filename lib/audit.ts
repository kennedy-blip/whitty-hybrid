// Lightweight cloud-side audit log (daemon keeps the full SQLite trail).
// In production, swap this for a real DB (Supabase/Postgres) — the shape stays the same.
type AuditEntry = { id: string; ts: string; tool: string; args: any; result: any; approved: boolean | null; source: string };
const store: AuditEntry[] = [];

export function logAudit(entry: Omit<AuditEntry, "id" | "ts">) {
  const e = { ...entry, id: Math.random().toString(36).slice(2, 10), ts: new Date().toISOString() };
  store.unshift(e);
  if (store.length > 500) store.pop();
  return e;
}
export function getAudit(limit = 100) { return store.slice(0, limit); }
