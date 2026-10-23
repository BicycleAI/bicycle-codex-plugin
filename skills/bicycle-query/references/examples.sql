-- Semantic SQL examples for the `query_*` tools.
--
-- Written against the Acme `commerce` domain (metrics revenue, order_count, aov,
-- session_count, conversion_rate; fields orders.region, orders.channel,
-- orders.method, orders.amount, customers.segment). In a real domain, take every
-- name from query_describe_model / query_search_fields first.
--
-- Each example starts with `-- example: <id>`. A `-- params: {...}` line is the
-- JSON to pass as the tool's `params` argument. `scripts/verify_examples.py` sends
-- every example to the engine in plan mode; each one must plan valid.

-- example: metric-by-dimension
-- One metric by one dimension over a fixed window (half-open: from <= time < to).
SELECT orders.region,
       MEASURE(revenue) AS revenue
FROM commerce
WHERE time >= '2026-09-01' AND time < '2026-09-15'
GROUP BY ALL
ORDER BY revenue DESC;

-- example: bare-total
-- One number: no dimension, so no GROUP BY.
SELECT MEASURE(revenue) AS revenue,
       MEASURE(order_count) AS orders
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '7' DAY AND time < CURRENT_DATE;

-- example: relative-window-series
-- A daily series over the last 7 whole days, relative to today in the domain timezone.
-- DATE_TRUNC grains: minute, hour, day, week (weeks start Monday).
SELECT DATE_TRUNC('day', time) AS day,
       MEASURE(order_count) AS orders,
       MEASURE(aov) AS aov
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '7' DAY AND time < CURRENT_DATE
GROUP BY ALL
ORDER BY day;

-- example: half-hour-series
-- Orders in 30-minute buckets over one day. TIME_BUCKET sizes: 5, 15, 30 minutes; 3, 6, 12 hours.
SELECT TIME_BUCKET(INTERVAL '30' MINUTE, time) AS bucket,
       MEASURE(order_count) AS orders
FROM commerce
WHERE time >= '2026-09-01' AND time < '2026-09-02'
GROUP BY ALL
ORDER BY bucket;

-- example: monthly-series
-- A calendar-month series. DATE_TRUNC now takes month, quarter and year alongside
-- minute, hour, day and week; check the metric's time_axis (query_describe_metric)
-- for the grains its axis supports before bucketing below day.
SELECT DATE_TRUNC('month', time) AS month,
       MEASURE(revenue) AS revenue
FROM commerce
WHERE time >= '2026-01-01' AND time < '2026-10-01'
GROUP BY ALL
ORDER BY month;

-- example: quarter-total
-- One quarter, one number: when there is nothing to break out, set the window to
-- the quarter's own bounds instead of bucketing with DATE_TRUNC.
SELECT MEASURE(revenue) AS revenue,
       MEASURE(order_count) AS orders
FROM commerce
WHERE time >= '2026-07-01' AND time < '2026-10-01';

-- example: filtered-top-n
-- Top 3 regions by revenue for two channels. Filters on fields go in WHERE.
SELECT orders.region,
       MEASURE(revenue) AS revenue
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
  AND orders.channel IN ('web', 'app')
GROUP BY ALL
ORDER BY revenue DESC
LIMIT 3;

-- example: contains-filter
-- A substring match on a field: CONTAINS, not LIKE (LIKE is refused in a semantic select).
SELECT orders.channel,
       MEASURE(revenue) AS revenue
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
  AND CONTAINS(orders.region, 'A')
GROUP BY ALL
ORDER BY revenue DESC;

-- example: running-total
-- A cumulative sum over a daily series. An ascending ORDER BY inside an aggregate
-- window must say NULLS FIRST (the venues disagree otherwise).
WITH daily AS (
  SELECT DATE_TRUNC('day', time) AS day, MEASURE(revenue) AS revenue
  FROM commerce
  WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
  GROUP BY ALL
)
SELECT day,
       revenue,
       SUM(revenue) OVER (ORDER BY day NULLS FIRST) AS running_revenue
FROM daily
ORDER BY day;

-- example: top-n-per-group
-- The top 2 channels inside every region: rank over the semantic select's result.
WITH by_channel AS (
  SELECT orders.region, orders.channel, MEASURE(revenue) AS revenue
  FROM commerce
  WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
  GROUP BY ALL
)
SELECT region, channel, revenue
FROM by_channel
QUALIFY ROW_NUMBER() OVER (PARTITION BY region ORDER BY revenue DESC) <= 2
ORDER BY region, revenue DESC;

-- example: share-of-total
-- Each region's share of revenue. SUM over revenue is allowed because it adds up;
-- SUM or AVG over a ratio such as aov is refused (NON_ADDITIVE_REAGGREGATION).
WITH by_region AS (
  SELECT orders.region, MEASURE(revenue) AS revenue
  FROM commerce
  WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
  GROUP BY ALL
)
SELECT region,
       revenue,
       revenue / SUM(revenue) OVER () AS share
FROM by_region
ORDER BY share DESC;

-- example: period-over-period
-- This period against the one before: two semantic selects, one per window, joined
-- in the outer query. FULL OUTER JOIN keeps a region present in only one period.
WITH cur AS (
  SELECT orders.region, MEASURE(revenue) AS revenue
  FROM commerce
  WHERE time >= '2026-09-08' AND time < '2026-09-15'
  GROUP BY ALL
),
prev AS (
  SELECT orders.region, MEASURE(revenue) AS revenue
  FROM commerce
  WHERE time >= '2026-09-01' AND time < '2026-09-08'
  GROUP BY ALL
)
SELECT COALESCE(cur.region, prev.region) AS region,
       cur.revenue AS revenue,
       prev.revenue AS prev_revenue,
       cur.revenue - prev.revenue AS change,
       cur.revenue / NULLIF(prev.revenue, 0) - 1 AS growth
FROM cur
FULL OUTER JOIN prev ON cur.region = prev.region
ORDER BY growth DESC NULLS LAST;

-- example: having
-- Filter on an aggregate: a condition on a measure belongs in HAVING, never WHERE.
SELECT orders.region,
       MEASURE(order_count) AS orders,
       MEASURE(revenue) AS revenue
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
GROUP BY ALL
HAVING MEASURE(order_count) >= 10
ORDER BY revenue DESC;

-- example: two-metrics-ratio
-- Metrics from different datasets in one select, grouped by a dimension both reach.
SELECT DATE_TRUNC('week', time) AS week,
       MEASURE(order_count) AS orders,
       MEASURE(session_count) AS sessions,
       MEASURE(conversion_rate) AS conversion_rate
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
GROUP BY ALL
ORDER BY week;

-- example: row-select
-- Rows, not aggregates: a select with no MEASURE. Always runs on the warehouse,
-- so it may come back as a consent question.
SELECT orders.order_id,
       orders.region,
       orders.amount
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '1' DAY AND time < CURRENT_DATE
  AND orders.amount > 100
ORDER BY orders.amount DESC
LIMIT 10;

-- example: distinct-values
-- The distinct values of a dimension, for a literal filter value
-- (query_dimension_values does the same).
SELECT DISTINCT orders.channel
FROM commerce
WHERE time >= CURRENT_DATE - INTERVAL '28' DAY AND time < CURRENT_DATE
LIMIT 50;

-- example: parameters
-- A reusable statement: values are `:name` parameters, never pasted into the text.
-- Time parameters must be declared with their type; a bare string is a string.
-- params: {"since": {"type": "timestamp", "value": "2026-09-01"}, "until": {"type": "timestamp", "value": "2026-09-15"}, "channel": "web"}
SELECT orders.region,
       MEASURE(revenue) AS revenue
FROM commerce
WHERE time >= :since AND time < :until
  AND orders.channel = :channel
GROUP BY ALL
ORDER BY revenue DESC;
