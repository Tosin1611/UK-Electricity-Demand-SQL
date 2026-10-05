-- =====================================================================
-- 04  ANSWER BUSINESS QUESTIONS   (EXERCISES)
-- Run 02 and 03 first - these use fact_demand, dim_date and v_daily_kpis.
-- Each question names the SQL technique it practises. These are the
-- techniques that come up in data-analyst SQL interviews.
-- =====================================================================

-- B1. What were the 5 highest-demand half-hours of the year, and when?
-- Technique: ORDER BY ... DESC + LIMIT


-- B2. On average, how much lower is weekend demand than weekday demand (in %)?
-- Technique: CASE inside an aggregate, e.g. AVG(CASE WHEN is_weekend = 1 THEN avg_demand_mw END)


-- B3. For each month, which hour of the day has the highest average demand?
-- Technique: ROW_NUMBER() OVER (PARTITION BY month ORDER BY ... DESC), then keep rn = 1
-- Hint: you can use AVG(...) inside the ORDER BY of a window function.


-- B4. Show each day's peak demand next to its 7-day rolling average.
-- Technique: AVG(...) OVER (ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)


-- B5. Anomaly detection: which days have an average demand more than
--     2 standard deviations from their month's average? Why might they be unusual?
-- Technique: a CTE (WITH month_stats AS (...)) then JOIN back to the daily view.
-- Note: SQLite has no STDEV(). Use SQRT(AVG(x*x) - AVG(x)*AVG(x)).


-- B6. Does midday solar reduce the demand the grid sees? Compare average
--     12:00-14:00 demand on the 10 sunniest vs 10 least sunny summer weekdays.
-- Technique: CTE + two subqueries combined with UNION ALL


-- B7. YOUR OWN QUESTION. Write one question a Boeing stakeholder might ask
--     about a dataset like this, then answer it. Put it in your README.
