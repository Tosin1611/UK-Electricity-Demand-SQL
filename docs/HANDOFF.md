# Handoff: Refresh, Maintenance & Troubleshooting

This document is for whoever maintains the pipeline next. It covers how to refresh the data, what
"healthy" looks like, and how to investigate when something looks wrong.

## Refreshing the data

NESO publishes historic demand about **21 days in arrears**, so a weekly or monthly refresh is enough.

1. `python load_data.py`: re-pulls the full year from the API and **replaces** `raw_demand`.
2. `python run_sql.py sql/01_validate_raw_data.sql`: review the output (see "What healthy looks like").
3. `python run_sql.py sql/02_build_star_schema.sql`: rebuilds `dim_date` and `fact_demand`.
4. `python run_sql.py sql/03_kpi_views.sql`: rebuilds the KPI views.
5. `python export_for_powerbi.py`, then **Refresh** in Power BI.

Every step can be re-run safely (each script drops and rebuilds its own objects), so if a step fails,
fix the cause and re-run from that step.

## What healthy looks like

| Check | Expected |
|---|---|
| Rows in `raw_demand` vs `fact_demand` | Equal, unless validation found forecasts, duplicates or bad values |
| Total rows | (standard days × 48) + (46 for the last Sunday in March) + (50 for the last Sunday in October) |
| Forecast (`F`) rows | 0 |
| Duplicate (date, period) pairs | 0 |
| Nulls in `ND` | 0 |
| `v_data_quality` | **Empty** |

**Baseline at handoff (load of 4 Oct 2026):** 12,286 rows, 1 Jan – 13 Sep 2026, every check passing.

## Troubleshooting

**`v_data_quality` returns rows**
- `periods_missing` = 48 → the whole day is missing from the source. Check whether NESO has published
  it yet (data is ~21 days behind) before treating it as an error.
- `periods_missing` is small (1–2) → the source is missing specific half-hours. Look at the raw rows for
  that date in `raw_demand` and check the NESO portal for a revised file.
- Negative `periods_missing` → more periods than expected, probably duplicates that weren't removed.
  Re-run validation check 4.

**`raw_demand` rows ≠ `fact_demand` rows**
- The gap equals the rows removed by the cleaning rules. Re-run validation checks 3, 4 and 6 to see which
  rule removed them, and confirm that's expected.

**`load_data.py` fails**
- `HTTP 404` or an empty result → the resource ID has changed (NESO creates a new one each year). Find
  the current ID on the [Historic Demand Data page](https://www.neso.energy/data-portal/historic-demand-data)
  and update `RESOURCE_ID`.
- Network or firewall errors → download the CSV from the portal and run
  `python load_data.py --csv <file>.csv`. Then confirm validation check 1 shows dates in `YYYY-MM-DD` format.

**A month's totals look far too low**
- Check whether it's a partial month (the most recent month always is). Compare averages, not totals.

## Known limitations
See the "Known limitations" section of the main [README](../README.md).
