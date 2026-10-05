-- =====================================================================
-- 02  TRANSFORM: BUILD THE STAR SCHEMA
-- Goal: turn raw_demand into a clean, analysis-ready "star schema":
--    dim_date     - one row per day, with calendar attributes
--    fact_demand  - one row per half-hour, cleaned and de-duplicated
-- This is the "T" in ETL. Re-runnable: it drops and rebuilds each time.
-- =====================================================================

DROP TABLE IF EXISTS fact_demand;
DROP TABLE IF EXISTS dim_date;

-- ---------------------------------------------------------------------
-- dim_date: one row per calendar day
-- strftime('%w') returns 0 = Sunday ... 6 = Saturday
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key        TEXT PRIMARY KEY,   -- 'YYYY-MM-DD'
    year            INTEGER,
    month           INTEGER,
    month_name      TEXT,
    day_of_week     INTEGER,            -- 0 = Sun
    day_name        TEXT,
    is_weekend      INTEGER,            -- 1 / 0
    periods_in_day  INTEGER,            -- expected: 46 / 48 / 50
    is_clock_change INTEGER             -- 1 on the two clock-change Sundays
);

-- Build the calendar from the first to the last date in the data using a
-- RECURSIVE CTE, so every day exists - even one with no data at all.
-- Expected periods come from the CALENDAR, not the data:
--   last Sunday of March   = 46 (clocks go forward)
--   last Sunday of October = 50 (clocks go back)
--   every other day        = 48
INSERT INTO dim_date
WITH RECURSIVE calendar(d) AS (
    SELECT MIN(SETTLEMENT_DATE) FROM raw_demand
    UNION ALL
    SELECT date(d, '+1 day') FROM calendar
    WHERE d < (SELECT MAX(SETTLEMENT_DATE) FROM raw_demand)
),
labelled AS (
    SELECT d,
           CASE WHEN strftime('%m', d) = '03' AND strftime('%w', d) = '0'
                     AND CAST(strftime('%d', d) AS INTEGER) > 24 THEN 46
                WHEN strftime('%m', d) = '10' AND strftime('%w', d) = '0'
                     AND CAST(strftime('%d', d) AS INTEGER) > 24 THEN 50
                ELSE 48 END AS periods
    FROM calendar
)
SELECT d,
       CAST(strftime('%Y', d) AS INTEGER),
       CAST(strftime('%m', d) AS INTEGER),
       CASE strftime('%m', d)
            WHEN '01' THEN 'Jan' WHEN '02' THEN 'Feb' WHEN '03' THEN 'Mar'
            WHEN '04' THEN 'Apr' WHEN '05' THEN 'May' WHEN '06' THEN 'Jun'
            WHEN '07' THEN 'Jul' WHEN '08' THEN 'Aug' WHEN '09' THEN 'Sep'
            WHEN '10' THEN 'Oct' WHEN '11' THEN 'Nov' ELSE 'Dec' END,
       CAST(strftime('%w', d) AS INTEGER),
       CASE strftime('%w', d)
            WHEN '0' THEN 'Sun' WHEN '1' THEN 'Mon' WHEN '2' THEN 'Tue'
            WHEN '3' THEN 'Wed' WHEN '4' THEN 'Thu' WHEN '5' THEN 'Fri'
            ELSE 'Sat' END,
       CASE WHEN strftime('%w', d) IN ('0', '6') THEN 1 ELSE 0 END,
       periods,
       CASE WHEN periods <> 48 THEN 1 ELSE 0 END
FROM labelled;

-- ---------------------------------------------------------------------
-- fact_demand: cleaned half-hourly measurements
-- Cleaning rules (also documented in README.md):
--   1. Actuals only (FORECAST_ACTUAL_INDICATOR = 'A')
--   2. One row per (date, period): duplicates removed, keeping the latest load
--   3. Rows with no demand value or demand <= 0 are excluded
--   4. Settlement period converted to a time label (period 1 = 00:00)
-- ---------------------------------------------------------------------
CREATE TABLE fact_demand (
    date_key            TEXT    NOT NULL REFERENCES dim_date(date_key),
    settlement_period   INTEGER NOT NULL,
    period_start        TEXT,       -- e.g. '2026-01-01 00:30'
    hour_of_day         INTEGER,
    national_demand_mw  INTEGER,
    transmission_demand_mw INTEGER,
    eng_wales_demand_mw INTEGER,
    embedded_wind_mw    INTEGER,
    embedded_solar_mw   INTEGER,
    solar_capacity_mw   INTEGER,
    PRIMARY KEY (date_key, settlement_period)
);

INSERT INTO fact_demand
SELECT SETTLEMENT_DATE,
       SETTLEMENT_PERIOD,
       strftime('%Y-%m-%d %H:%M', SETTLEMENT_DATE, '+' || ((SETTLEMENT_PERIOD - 1) * 30) || ' minutes'),
       (SETTLEMENT_PERIOD - 1) / 2,           -- integer division: periods 1-2 -> hour 0
       ND, TSD, ENGLAND_WALES_DEMAND,
       EMBEDDED_WIND_GENERATION, EMBEDDED_SOLAR_GENERATION, EMBEDDED_SOLAR_CAPACITY
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY SETTLEMENT_DATE, SETTLEMENT_PERIOD
                              ORDER BY loaded_at DESC, rowid DESC) AS rn
    FROM raw_demand AS r
    WHERE FORECAST_ACTUAL_INDICATOR = 'A'
      AND ND IS NOT NULL
      AND ND > 0
) AS ranked
WHERE rn = 1;
-- Note: on clock-change days the period -> clock-time conversion is approximate
-- (a 46- or 50-period day doesn't map neatly onto 00:00-23:30). Flagged via
-- dim_date.is_clock_change so you can exclude those days from hourly analysis.

CREATE INDEX idx_fact_hour ON fact_demand(hour_of_day);

-- Check the build: row counts should reconcile with the raw layer.
SELECT (SELECT COUNT(*) FROM raw_demand)  AS raw_rows,
       (SELECT COUNT(*) FROM fact_demand) AS fact_rows,
       (SELECT COUNT(*) FROM dim_date)    AS days;
