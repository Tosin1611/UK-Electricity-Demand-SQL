"""
STEP 4 - EXPORT FOR POWER BI
Writes each dashboard view to a CSV in exports/ so Power BI Desktop can
load it with Get Data > Text/CSV (no database driver needed).

    python export_for_powerbi.py
"""
import csv
import sqlite3
from pathlib import Path

HERE = Path(__file__).parent
VIEWS = ["v_daily_kpis", "v_hourly_profile", "v_monthly_summary", "v_data_quality"]


def export(db_path=HERE / "neso.db", out_dir=HERE / "exports"):
    out_dir.mkdir(exist_ok=True)
    con = sqlite3.connect(db_path)
    for view in VIEWS:
        cur = con.execute(f"SELECT * FROM {view}")
        rows = cur.fetchall()
        with open(out_dir / f"{view}.csv", "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow([c[0] for c in cur.description])
            w.writerows(rows)
        print(f"  {view}.csv  ({len(rows):,} rows)")
    con.close()


if __name__ == "__main__":
    export()
