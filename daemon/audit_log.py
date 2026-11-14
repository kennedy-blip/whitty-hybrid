"""Local SQLite audit trail — every command, output, and approval decision."""
import sqlite3, json, time, os
DB_PATH = os.path.join(os.path.dirname(__file__), "audit.db")

def _conn():
    c = sqlite3.connect(DB_PATH)
    c.execute("""CREATE TABLE IF NOT EXISTS audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL, tool TEXT, args TEXT,
        result TEXT, approved INTEGER, source TEXT)""")
    return c

def log(tool: str, args: dict, result, approved=None, source="daemon"):
    try:
        c = _conn()
        c.execute("INSERT INTO audit (ts, tool, args, result, approved, source) VALUES (?,?,?,?,?,?)",
                  (time.time(), tool, json.dumps(args, default=str), json.dumps(result, default=str),
                   None if approved is None else int(approved), source))
        c.commit(); c.close()
    except Exception as e:
        print(f"[audit] failed: {e}")

def recent(limit=100):
    try:
        c = _conn()
        rows = c.execute("SELECT ts, tool, args, result, approved, source FROM audit ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        c.close()
        return [{"ts": r[0], "tool": r[1], "args": json.loads(r[2] or "{}"), "result": json.loads(r[3] or "null"), "approved": r[4], "source": r[5]} for r in rows]
    except Exception:
        return []
