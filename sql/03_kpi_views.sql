-- =====================================================================
-- 03  KPI VIEWS FOR THE DASHBOARD
-- A view is a saved query. Power BI reads these (exported to CSV),
-- so all business logic lives in SQL, in one documented place.
-- =====================================================================

-- Daily KPIs: one row per day
DROP VIEW IF EXISTS v_daily_kpis;
CREATE VIEW v_daily_kpis AS
SELECT d.date_key,
       d.month_name,
       d.day_name,
       d.is_weekend,
       MAX(f.national_demand_mw)                  AS peak_demand_mw,
       MIN(f.national_demand_mw)                  AS min_demand_mw,
       ROUND(AVG(f.national_demand_mw))           AS avg_demand_mw,
       -- Energy (MWh) = sum of MW x 0.5 hours per half-hour period
       ROUND(SUM(f.national_demand_mw) * 0.5)     AS demand_mwh,
       ROUND(SUM(f.embedded_solar_mw) * 0.5)      AS solar_mwh,
       ROUND(SUM(f.embedded_wind_mw) * 0.5)       AS wind_mwh,
       ROUND(100.0 * SUM(f.embedded_solar_mw + f.embedded_wind_mw)
             / SUM(f.national_demand_mw + f.embedded_solar_mw + f.embedded_wind_mw), 1)
                                                  AS embedded_renewables_pct,
       COUNT(*)                                   AS periods_recorded,
       d.periods_in_day                           AS periods_expected
FROM fact_demand AS f
JOIN dim_date    AS d ON d.date_key = f.date_key
GROUP BY d.date_key;

-- Average demand shape across the day, weekday vs weekend
DROP VIEW IF EXISTS v_hourly_profile;
CREATE VIEW v_hourly_profile AS
SELECT f.hour_of_day,
       CASE WHEN d.is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       ROUND(AVG(f.national_demand_mw)) AS avg_demand_mw,
       ROUND(AVG(f.embedded_solar_mw))  AS avg_solar_mw
FROM fact_demand AS f
JOIN dim_date    AS d ON d.date_key = f.date_key
WHERE d.is_clock_change = 0               -- exclude the awkward 46/50-period days
GROUP BY f.hour_of_day, day_type;

-- Monthly summary with month-on-month change (window function LAG)
DROP VIEW IF EXISTS v_monthly_summary;
CREATE VIEW v_monthly_summary AS
SELECT month,
       month_name,
       avg_demand_mw,
       peak_demand_mw,
       solar_mwh,
       ROUND(100.0 * (avg_demand_mw - LAG(avg_demand_mw) OVER (ORDER BY month))
             / LAG(avg_demand_mw) OVER (ORDER BY month), 1) AS avg_demand_change_pct
FROM (
    SELECT d.month, d.month_name,
           ROUND(AVG(f.national_demand_mw))      AS avg_demand_mw,
           MAX(f.national_demand_mw)             AS peak_demand_mw,
           ROUND(SUM(f.embedded_solar_mw) * 0.5) AS solar_mwh
    FROM fact_demand AS f
    JOIN dim_date    AS d ON d.date_key = f.date_key
    GROUP BY d.month, d.month_name
);

-- Data-quality view: days whose recorded periods don't match what's expected.
-- Expected to be empty. Any row here needs investigating before the numbers are trusted.
DROP VIEW IF EXISTS v_data_quality;
CREATE VIEW v_data_quality AS
SELECT d.date_key,
       COUNT(f.settlement_period)                     AS periods_recorded,
       d.periods_in_day                               AS periods_expected,
       d.periods_in_day - COUNT(f.settlement_period)  AS periods_missing
FROM dim_date AS d
LEFT JOIN fact_demand AS f ON f.date_key = d.date_key   -- LEFT JOIN keeps days with no data at all
GROUP BY d.date_key
HAVING COUNT(f.settlement_period) <> d.periods_in_day;

-- Quick look
SELECT * FROM v_daily_kpis ORDER BY date_key DESC LIMIT 7;
SELECT * FROM v_monthly_summary;
