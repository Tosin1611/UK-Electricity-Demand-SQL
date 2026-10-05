-- =====================================================================
-- 04  BUSINESS QUESTIONS
-- Analysis on top of the star schema and KPI views (run 02 and 03 first).
-- Each question notes the SQL technique used and the result from the
-- 2026 load (1 Jan - 13 Sep 2026).
-- =====================================================================

-- B1. What were the 5 highest-demand half-hours of the year, and when?
-- Technique: ORDER BY ... DESC + LIMIT
SELECT period_start, national_demand_mw
FROM fact_demand
ORDER BY national_demand_mw DESC
LIMIT 5;
-- RESULT: highest half-hour was 47,382 MW, in January.

-- B2. On average, how much lower is weekend demand than weekday demand (in %)?
-- Technique: CASE inside an aggregate
SELECT ROUND(AVG(CASE WHEN is_weekend = 0 THEN avg_demand_mw END)) AS weekday_avg_mw,
       ROUND(AVG(CASE WHEN is_weekend = 1 THEN avg_demand_mw END)) AS weekend_avg_mw,
       ROUND(100.0 * (1 - AVG(CASE WHEN is_weekend = 1 THEN avg_demand_mw END)
                        / AVG(CASE WHEN is_weekend = 0 THEN avg_demand_mw END)), 1) AS weekend_drop_pct
FROM v_daily_kpis;

-- B3. For each month, which hour of the day has the highest average demand?
-- Technique: ROW_NUMBER() OVER (PARTITION BY ...) to pick the top row per group
SELECT month_name, hour_of_day, avg_demand_mw
FROM (
    SELECT d.month, d.month_name, f.hour_of_day,
           ROUND(AVG(f.national_demand_mw)) AS avg_demand_mw,
           ROW_NUMBER() OVER (PARTITION BY d.month
                              ORDER BY AVG(f.national_demand_mw) DESC) AS rn
    FROM fact_demand f
    JOIN dim_date d ON d.date_key = f.date_key
    GROUP BY d.month, d.month_name, f.hour_of_day
)
WHERE rn = 1
ORDER BY month;

-- B4. Each day's peak demand next to its 7-day rolling average.
-- Technique: window frame - AVG(...) OVER (ORDER BY ... ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
SELECT date_key, peak_demand_mw,
       ROUND(AVG(peak_demand_mw) OVER (ORDER BY date_key
                                       ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)) AS peak_7day_avg_mw
FROM v_daily_kpis
ORDER BY date_key;

-- B5. Anomaly detection (first attempt): which days have an average demand more than
--     2 standard deviations from their month's average?
-- Technique: CTE (WITH month_stats AS (...)) joined back to the daily view.
-- |z| > 2 is tested as (x - mean)^2 > 4 * variance, which avoids SQRT().
WITH month_stats AS (
    SELECT d.month,
           AVG(k.avg_demand_mw) AS mean_mw,
           AVG(k.avg_demand_mw * k.avg_demand_mw) - AVG(k.avg_demand_mw) * AVG(k.avg_demand_mw) AS var_mw
    FROM v_daily_kpis k
    JOIN dim_date d ON d.date_key = k.date_key
    GROUP BY d.month
)
SELECT k.date_key, k.day_name, k.avg_demand_mw,
       ROUND(s.mean_mw)                   AS month_mean_mw,
       ROUND(k.avg_demand_mw - s.mean_mw) AS diff_mw
FROM v_daily_kpis k
JOIN dim_date d    ON d.date_key = k.date_key
JOIN month_stats s ON s.month = d.month
WHERE (k.avg_demand_mw - s.mean_mw) * (k.avg_demand_mw - s.mean_mw) > 4 * s.var_mw
ORDER BY ABS(k.avg_demand_mw - s.mean_mw) DESC;
-- RESULT: 6 days flagged. Mostly weekends (22 Feb, 13 Jun, 28 Mar, 24 May) plus New Year's Day.
-- 1 Apr flagged HIGH because demand falls through spring, so early April sits above the April mean.
-- Limitation: the baseline mixes weekdays and weekends, so ordinary weekends look anomalous
-- and weekday bank holidays are hidden. Fixed in B5b.

-- B5b. Improved anomaly detection: compare weekdays with weekdays and weekends with weekends.
-- Technique: same CTE, grouped and joined on month AND day type.
WITH baseline AS (
    SELECT d.month, d.is_weekend,
           AVG(k.avg_demand_mw) AS mean_mw,
           AVG(k.avg_demand_mw * k.avg_demand_mw) - AVG(k.avg_demand_mw) * AVG(k.avg_demand_mw) AS var_mw
    FROM v_daily_kpis k
    JOIN dim_date d ON d.date_key = k.date_key
    GROUP BY d.month, d.is_weekend
)
SELECT k.date_key, k.day_name, k.avg_demand_mw,
       ROUND(b.mean_mw)                   AS baseline_mw,
       ROUND(k.avg_demand_mw - b.mean_mw) AS diff_mw
FROM v_daily_kpis k
JOIN dim_date d ON d.date_key = k.date_key
JOIN baseline b ON b.month = d.month AND b.is_weekend = d.is_weekend
WHERE (k.avg_demand_mw - b.mean_mw) * (k.avg_demand_mw - b.mean_mw) > 4 * b.var_mw
ORDER BY ABS(k.avg_demand_mw - b.mean_mw) DESC;
-- RESULT: 10 days flagged. Weekday bank holidays now stand out: New Year's Day (-6,472 MW)
-- and the late-May bank holiday (-3,035 MW). 22 Feb is unusually low even for a Sunday (likely weather).
-- All HIGH anomalies (6 Mar, 9 Mar, 1 Apr) fall early in spring months while demand is still falling,
-- so a monthly baseline overstates them. Next step: a rolling baseline (previous 4 weeks, same day type).

-- B6. Does midday solar reduce the demand the grid sees? Compare average
--     12:00-14:00 demand on the 10 sunniest vs 10 least sunny summer weekdays.
-- Technique: CTE + two subqueries combined with UNION ALL
WITH midday AS (
    SELECT f.date_key,
           AVG(f.national_demand_mw) AS midday_demand_mw,
           AVG(f.embedded_solar_mw)  AS midday_solar_mw
    FROM fact_demand f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.hour_of_day BETWEEN 12 AND 13
      AND d.month IN (6, 7, 8)
      AND d.is_weekend = 0
    GROUP BY f.date_key
)
SELECT 'Sunniest 10 days' AS grp, ROUND(AVG(midday_solar_mw)) AS solar_mw, ROUND(AVG(midday_demand_mw)) AS demand_mw
FROM (SELECT * FROM midday ORDER BY midday_solar_mw DESC LIMIT 10)
UNION ALL
SELECT 'Least sunny 10 days', ROUND(AVG(midday_solar_mw)), ROUND(AVG(midday_demand_mw))
FROM (SELECT * FROM midday ORDER BY midday_solar_mw ASC LIMIT 10);
-- RESULT: Sunniest 10 summer weekdays: 14,858 MW solar, 19,720 MW grid demand at midday.
-- Least sunny 10: 7,035 MW solar, 24,400 MW demand. +7,823 MW solar ~ -4,680 MW demand (~0.6 MW per MW).
-- Caveat: correlation only. Sunny days are also warmer and brighter, so temperature is a confounder.

-- B7. Which day of the week has the highest average demand, and how big is the
--     weekday/weekend gap?
-- Technique: GROUP BY + CASE in ORDER BY (SQLite numbers Sunday as 0; sort it as 7 for Mon-Sun order)
SELECT d.day_name,
       ROUND(AVG(k.avg_demand_mw))  AS avg_demand_mw,
       ROUND(AVG(k.peak_demand_mw)) AS avg_peak_mw,
       COUNT(*)                     AS days_counted
FROM v_daily_kpis k
JOIN dim_date d ON d.date_key = k.date_key
GROUP BY d.day_of_week, d.day_name
ORDER BY CASE d.day_of_week WHEN 0 THEN 7 ELSE d.day_of_week END;
-- RESULT: Weekend demand is ~11% lower than weekdays. Thursday is highest (26,423 MW).
-- Monday and Friday are the lowest weekdays, pulled down by bank holidays (Easter, May, August).
