-- =====================================================================
-- 01  VALIDATE RAW DATA
-- Profiles raw_demand and checks data quality BEFORE anything is built
-- on top of it: volume, duplicates, completeness, nulls and anomalies.
--
-- Results from the 2026 load (1 Jan - 13 Sep 2026) are noted under
-- each check.
-- =====================================================================

-- 1. Volume and coverage
SELECT COUNT(*)              AS row_count,
       MIN(SETTLEMENT_DATE)  AS first_date,
       MAX(SETTLEMENT_DATE)  AS last_date
FROM raw_demand;
-- RESULT: 12,286 rows, 2026-01-01 to 2026-09-13 (256 days).

-- 2. Sample of the raw data
SELECT *
FROM raw_demand
ORDER BY SETTLEMENT_DATE, SETTLEMENT_PERIOD
LIMIT 10;

-- 3. Actuals vs forecasts
SELECT FORECAST_ACTUAL_INDICATOR, COUNT(*) AS n
FROM raw_demand
GROUP BY FORECAST_ACTUAL_INDICATOR;
-- RESULT: all rows are actuals ('A').

-- 4. Duplicate half-hours
SELECT SETTLEMENT_DATE, SETTLEMENT_PERIOD, COUNT(*) AS copies
FROM raw_demand
GROUP BY SETTLEMENT_DATE, SETTLEMENT_PERIOD
HAVING COUNT(*) > 1;
-- RESULT: no duplicates.

-- 5. Completeness: days without the standard 48 half-hour periods
SELECT SETTLEMENT_DATE, COUNT(*) AS periods
FROM raw_demand
GROUP BY SETTLEMENT_DATE
HAVING COUNT(*) <> 48
ORDER BY SETTLEMENT_DATE;
-- RESULT: only 2026-03-29, with 46 periods. That is the BST clock change
-- (a 23-hour day), so it is expected, not missing data. No real gaps.
-- (An earlier Python analysis had flagged 2 "missing timestamps" on this
-- date; the cause was timestamp logic assuming 48 periods every day.)

-- 6. Missing values in key measures
SELECT SUM(CASE WHEN ND IS NULL THEN 1 ELSE 0 END)                        AS null_nd,
       SUM(CASE WHEN EMBEDDED_SOLAR_GENERATION IS NULL THEN 1 ELSE 0 END) AS null_solar,
       SUM(CASE WHEN EMBEDDED_WIND_GENERATION IS NULL THEN 1 ELSE 0 END)  AS null_wind
FROM raw_demand;
-- RESULT: 0 nulls in all three columns.

-- 7. Range check on national demand (MW)
SELECT MIN(ND) AS min_mw, MAX(ND) AS max_mw, ROUND(AVG(ND)) AS avg_mw
FROM raw_demand;

-- 8. Impossible or suspicious values:
--    non-positive demand, or solar output reported at night
SELECT SETTLEMENT_DATE, SETTLEMENT_PERIOD, ND, EMBEDDED_SOLAR_GENERATION
FROM raw_demand
WHERE ND <= 0
   OR (SETTLEMENT_PERIOD IN (1, 2, 3, 4, 47, 48) AND EMBEDDED_SOLAR_GENERATION > 0);

-- 9. Settlement periods outside the valid range (1-50)
SELECT SETTLEMENT_PERIOD, COUNT(*) AS n
FROM raw_demand
WHERE SETTLEMENT_PERIOD NOT BETWEEN 1 AND 50
GROUP BY SETTLEMENT_PERIOD;
