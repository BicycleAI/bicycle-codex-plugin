# Studio SQL models

Use this reference only when discovery identifies the model as Studio SQL (v1),
or its describe hint uses metric columns and `$name` parameters. This is a current
API language selected by the model, never a retry strategy for failed semantic SQL.
Do not change routing, sync a model or assume semantic-layer features are enabled.

## Discover and compile

Copy the exact metric `column`, dimension names and `time column` from
`query_describe_model`, `query_describe_metric` and `query_search_fields`. Use the
described `FROM` identifier, double-quoted when needed. For a model whose described
columns are `total_revenue` and `region`, and time column is `order_date`:

```sql
SELECT region, total_revenue
FROM shop
WHERE order_date >= $since AND order_date < $until
ORDER BY total_revenue DESC LIMIT 10
```

Pass plain values in `params`, e.g.
`{"since": "2026-09-01T00:00:00Z", "until": "2026-09-08T00:00:00Z"}`.
Every query must include a time range. If none was requested, compute the last
7 whole days in the intended reporting zone, supply explicit offset-bearing bounds,
and disclose the dates and zone. The v1 tools reject the `timezone` argument.

Use `query_compile` or `query_explain` before running a new statement. Metric
columns are already aggregated: use them directly, without `MEASURE`, `SUM(metric)`
or `GROUP BY ALL`. Additional selected dimensions define the grouping.
`date_trunc('day', order_date) AS day` gives a daily series when supported by the
metric's cache grain. Do not use the v2 examples, CTEs, joins, subqueries, window
functions or row-only selects; unsupported constructs are compile errors. For
comparisons, query the two windows separately and align complete results by their
dimension values. Do not re-total ratios or averages.

## Run and read

Use `query_run` with `cache_only: true`. A cache miss is a limitation to report;
do not set `cache_only: false`, trigger hydration or attach `consent` to bypass it.
The `consent` argument belongs only to v2. Keep the original dates when a result
is empty, even if the model's availability ended earlier.

The fetch limit is `max_rows` (default 200, at most 50,000); `show_rows` controls
the displayed table (default 50, at most 200). Check both truncation notices before
claiming a total or ranking is complete. Read values by their column names and keep
the full returned precision until presenting the answer. Ratios may already be
percentage points; confirm the definition and unit rather than multiplying by 100.

When compilation shows multiple backend queries, avoid `ORDER BY … LIMIT` for a
combined ranking: fetch the complete bounded result, then rank locally only if it
is untruncated. Otherwise split the question or explain the limitation. Select at
most one property per entity per query; spot-check entity values with
`query_dimension_values`. A one-day entity breakdown needs a daily bucket and a
check of the actual returned days.

Relay **Check these columns** warnings. A blank numeric cell means the backend
returned no row for that metric at that grouping. For a count, the tool explicitly
says this means zero; disclose that interpretation. Do not convert missing rates,
averages, failed queries or other NULLs into zero. A positional `column_1` or a
column warning requires checking the compiled query and field values before using
that column as a business label.

For computation details, quote the exact backend query from an existing
`query_compile` or `query_explain` result. A v1 `query_run` may only point to
`query_compile`; do not invent a v2 reference id or **How this was computed** block.
Compilation can show the backend query without executing it again.

Compile issues such as `parse_error`, `missing_param`, `time_range_required`,
`unknown_dimension`, `dimension_not_in_cube`, `no_joins` and `no_subqueries` describe
the correction. Apply it without changing language, identity, dates or permissions.
Stop if the same correction fails twice; 401/403 require reconnecting the account.
