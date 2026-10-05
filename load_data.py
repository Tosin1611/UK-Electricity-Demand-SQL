"""
STEP 1 - EXTRACT + LOAD
Pulls GB half-hourly electricity demand data from the NESO public API
and loads it, untouched, into a SQLite database table called raw_demand.

Uses only Python's standard library - no pip installs needed.

Run it:
    python load_data.py                 # 2026 data (default)
    python load_data.py --csv file.csv  # load a CSV you downloaded from the NESO website instead

Output: neso.db in this folder (open it with DB Browser for SQLite).
"""
import argparse
import csv
import json
import sqlite3
import urllib.parse
import urllib.request
from pathlib import Path

API_URL = "https://api.neso.energy/api/3/action/datastore_search"
RESOURCE_ID = "8a4a771c-3929-4e56-93ad-cdf13219dea5"  # Historic Demand Data 2026
PAGE_SIZE = 5000
DB_PATH = Path(__file__).parent / "neso.db"

# The columns we keep from the source (the API returns ~24; these are the useful ones)
COLUMNS = [
    "SETTLEMENT_DATE", "SETTLEMENT_PERIOD", "ND", "TSD", "ENGLAND_WALES_DEMAND",
    "EMBEDDED_WIND_GENERATION", "EMBEDDED_WIND_CAPACITY",
    "EMBEDDED_SOLAR_GENERATION", "EMBEDDED_SOLAR_CAPACITY",
    "FORECAST_ACTUAL_INDICATOR",
]


def fetch_from_api(resource_id=RESOURCE_ID):
    """Page through the API until every record has been collected."""
    records, offset = [], 0
    while True:
        query = urllib.parse.urlencode(
            {"resource_id": resource_id, "limit": PAGE_SIZE, "offset": offset})
        with urllib.request.urlopen(f"{API_URL}?{query}", timeout=60) as resp:
            payload = json.load(resp)
        if not payload.get("success"):
            raise RuntimeError(f"API returned an error: {payload}")
        batch = payload["result"]["records"]
        records.extend(batch)
        total = payload["result"].get("total", len(records))
        print(f"  fetched {len(records):,} of {total:,}")
        if not batch or len(records) >= total:
            return records
        offset += PAGE_SIZE


def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def load(records, db_path=DB_PATH):
    """Write records into raw_demand exactly as received (raw layer = no cleaning)."""
    con = sqlite3.connect(db_path)
    con.execute("DROP TABLE IF EXISTS raw_demand")
    con.execute(f"""
        CREATE TABLE raw_demand (
            {', '.join(f'{c} TEXT' if c in ('SETTLEMENT_DATE', 'FORECAST_ACTUAL_INDICATOR')
                       else f'{c} INTEGER' for c in COLUMNS)},
            loaded_at TEXT DEFAULT CURRENT_TIMESTAMP
        )""")
    rows = []
    for r in records:
        row = [r.get(c) for c in COLUMNS]
        # Dates arrive as '2026-01-01' or '2026-01-01T00:00:00' - keep the date part only
        row[0] = str(row[0])[:10] if row[0] else None
        rows.append(row)
    con.executemany(
        f"INSERT INTO raw_demand ({', '.join(COLUMNS)}) VALUES ({', '.join('?' * len(COLUMNS))})",
        rows)
    con.commit()
    n = con.execute("SELECT COUNT(*) FROM raw_demand").fetchone()[0]
    con.close()
    print(f"Loaded {n:,} rows into raw_demand in {db_path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", help="load from a downloaded CSV instead of the API")
    args = ap.parse_args()
    if args.csv:
        data = read_csv(args.csv)
    else:
        print("Fetching from the NESO API...")
        data = fetch_from_api()
    load(data)
