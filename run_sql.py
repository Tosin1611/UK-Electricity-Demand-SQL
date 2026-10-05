"""
Run every statement in a .sql file against neso.db and print the results.
Handy if you'd rather work in VS Code than DB Browser.

    python run_sql.py sql/01_explore_and_validate.sql
"""
import sqlite3
import sys
from pathlib import Path

DB_PATH = Path(__file__).parent / "neso.db"


def run_file(path, db_path=DB_PATH, show=True):
    con = sqlite3.connect(db_path)
    script = Path(path).read_text(encoding="utf-8")
    buffer = ""
    for line in script.splitlines(keepends=True):
        buffer += line
        if sqlite3.complete_statement(buffer):
            stmt = buffer.strip()
            buffer = ""
            if not stmt or all(l.strip().startswith("--") or not l.strip() for l in stmt.splitlines()):
                continue
            cur = con.execute(stmt)
            if cur.description and show:
                cols = [c[0] for c in cur.description]
                rows = cur.fetchall()
                print("\n" + " | ".join(cols))
                print("-" * min(100, len(" | ".join(cols))))
                for r in rows[:25]:
                    print(" | ".join("" if v is None else str(v) for v in r))
                if len(rows) > 25:
                    print(f"... ({len(rows)} rows total)")
                if not rows:
                    print("(no rows)")
    con.commit()
    con.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python run_sql.py <file.sql>")
    run_file(sys.argv[1])
