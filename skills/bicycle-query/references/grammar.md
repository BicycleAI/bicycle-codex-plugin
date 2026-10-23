# Semantic SQL grammar

This reference applies only to semantic SQL (v2) models. For a Studio SQL (v1)
model, read [Studio SQL](studio-sql.md) instead.

A statement is one `SELECT`, optionally preceded by `WITH`. A **semantic select** is a
`SELECT … FROM <domain>`; it is the only place the model's names are read. Everything
around the semantic selects is ordinary SQL over their results.

## Inside a semantic select

| Construct | Rule |
|---|---|
| `FROM <domain>` | The domain name from `query_list_models`. Every semantic select in a statement names the same domain. Never joined, never aliased; compose through CTEs. |
| `MEASURE(metric)` | The only spelling of a metric. Takes one bare metric name. Allowed in the select list, `HAVING`, `QUALIFY` and `ORDER BY`; never in `WHERE` or `GROUP BY`. |
| `dataset.field` | Any field the domain exposes. `a.b.c`, bare field names and physical tables are refused. The output column is named after the field (`orders.region` → `region`) unless aliased. |
| `time` | Each metric's event time, read in the reporting zone (the query's `timezone`, else the domain's, else UTC). A field that is itself called `time` must be qualified. Read `time` only through `DATE_TRUNC`. |
| `DATE_TRUNC(g, time)` | `g` is `'minute'`, `'hour'`, `'day'`, `'week'` (weeks start Monday), `'month'`, `'quarter'` or `'year'`. One grain per select; the axis you bucket must support it (check with `query_explain`) — a `Date` axis floors at `day` and refuses anything finer with `GRAIN_NOT_SUPPORTED`. |
| `TIME_BUCKET(INTERVAL 'N' MINUTE\|HOUR, time)` | The multi-unit rungs: `5`, `15` or `30` minutes, `3`, `6` or `12` hours. Buckets start at local midnight in the reporting zone. The full ladder is 1m → 5m → 15m → 30m → 1h → 3h → 6h → 12h → 1d → 1w; any other size is `GRAIN_NOT_SUPPORTED`. Only as the time key of a select FROM the domain. |
| `WHERE time >= a AND time < b` | The window, half-open. A bound is a literal (`'2026-09-01'`, `'2026-09-01T06:00:00Z'`), a `:param`, or `CURRENT_DATE` / `CURRENT_TIMESTAMP` with an optional `± INTERVAL 'n' unit` (`minute`, `hour`, `day`, `week`, `month`, `year`). A bare bound is read at query time in the reporting zone; an offset on a bound fixes the instant but never sets the zone. A bound finer than a day-floor axis snaps outward to the day, disclosed as `snapped: true`. With no window, the domain's default (`last_7d`: 6 whole days plus today so far, from local midnight in the reporting zone) applies and is disclosed. |
| Other `WHERE` conditions | `dataset.field` compared with a value (`=`, `<>`, `<`, `<=`, `>`, `>=`), `IN (…)`, `BETWEEN`, `IS [NOT] NULL`, `CONTAINS(dataset.field, 'text')`, joined by `AND`, `OR`, `NOT`. Values are checked against the field's type. `LIKE` is refused here (`FILTER_NOT_PUSHABLE`): write `CONTAINS(dataset.field, 'text')`. |
| `GROUP BY` | `ALL`, a list, ordinals or aliases. Keys are `dataset.field` or the time bucket (`DATE_TRUNC` or `TIME_BUCKET` of `time`). |
| `HAVING` | Conditions on measures, such as `HAVING MEASURE(order_count) >= 10`. |
| `SELECT DISTINCT` / no `MEASURE` | A row select: rows of fields (or their distinct combinations). Warehouse only, always under consent where the connection is metered. A row select has no `time` axis: select the dataset's own time field (`orders.completed_at`); the window is still written on `time` in `WHERE`. |
| `ORDER BY`, `LIMIT n` | `LIMIT` is a positive whole number within the domain's row limit. No `OFFSET`. |

## Output column names

Each select's columns are what a CTE or the outer query reads, and what `query_run`
shows as headers:

| Projection | Column name |
|---|---|
| `expr AS name` | `name` |
| `dataset.field` | the field's own name (`orders.region` → `region`) |
| bare `MEASURE(x)` | `x` |
| bare `DATE_TRUNC(g, time)` or `TIME_BUCKET(…, time)` | `time` |
| any other unaliased expression | `column_<n>`, its position (`revenue * 2` third → `column_3`) |

Alias every computed column (`… AS growth`) so the name means something, and alias
fields whose names collide across datasets (`orders.region` and `order_tags.region`).
Two columns with the same output name are refused.

## The reporting zone

Pass `timezone` (an IANA name, e.g. `America/New_York`) to `query_run`,
`query_compile` or `query_explain` to read buckets, bare bounds, bare filter values,
`CURRENT_DATE` and default windows in that zone. Omit it and the domain's own zone
applies, else UTC; the answer discloses `{zone, source}`. Buckets and timestamps
come back with their offset (`2026-01-01T09:00:00+05:30`) — quote them exactly as
given. An offset written on a literal bound fixes that moment but never changes the
reporting zone.

## Around the semantic selects

| Allowed | Notes |
|---|---|
| `WITH name AS (…)` | Not recursive. A CTE may not be named after the domain or one of its datasets, or start with `__sl_`. |
| Joins between CTEs | `INNER`, `LEFT`, `RIGHT`, `FULL OUTER`, `CROSS`. No `NATURAL`, `ASOF` or `LATERAL`. |
| Window functions | `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `NTILE`, `PERCENT_RANK`, `CUME_DIST`, `LAG`, `LEAD`, `FIRST_VALUE`, and `SUM`/`AVG`/`MIN`/`MAX`/`COUNT` `OVER (…)`. An ascending `ORDER BY` inside an aggregate window needs `NULLS FIRST`. |
| `QUALIFY`, `HAVING`, `UNION [ALL]`, `INTERSECT`, `EXCEPT` | |
| Scalar functions | `ABS`, `ROUND`, `FLOOR`, `CEIL`, `SQRT`, `LN`, `EXP`, `POW`, `SIGN`, `COALESCE`, `NULLIF`, `UPPER`, `LOWER`, `LENGTH`, `TRIM(x, ' ')`, `SUBSTRING` (from 1), `CONCAT`, `REPLACE`, `LEFT`, `RIGHT`, `CASE`, `IF`, `CAST` to a scalar type. |
| Arithmetic | `+ - * / %`. A division is by `NULLIF(divisor, 0)` on every venue, so dividing by zero gives NULL. |

## Refused

`MEDIAN` and percentiles (declare a metric in the model), `FILTER (WHERE …)` (write
`SUM(CASE WHEN … END)`), `GREATEST`/`LEAST`, `LAST_VALUE`, `EXTRACT`, `DISTINCT ON`,
`OFFSET`, `PIVOT`, `UNNEST`, `ROLLUP`/`CUBE`/`GROUPING SETS`, `TRY_CAST`, `AT TIME
ZONE`, subqueries inside a semantic select, `*` from the domain, table functions and
file access, `ATTACH`/`COPY`/`PRAGMA`/`SET`, and more than one statement. The engine
refuses these with `SQL_NOT_ALLOWED` and says what to write instead.

Limits: 20,000 characters, 8 semantic selects, bounded nesting depth.

## Parameters

Write a parameter as `:name` (a lowercase identifier that is not a SQL keyword: use
`:since`, not `:from`). `?`, `$1` and `@x` are refused. Supply each one in `params`:

```json
{
  "since":   {"type": "timestamp", "value": "2026-09-01"},
  "until":   {"type": "timestamp", "value": "2026-09-15T00:00:00+05:30"},
  "channel": "web",
  "minimum": 10
}
```

- Types: `timestamp`, `date`, `string`, `number`, `boolean`. Each takes a `value` or a
  `default`. A bare JSON value is shorthand for its JSON type, so time parameters must
  be declared with `"type"`.
- A value with an offset is an exact instant; a bare value is wall-clock time in the
  domain timezone. The same holds for time literals written in the SQL.
- Every `:name` needs a value, and every supplied name must appear in the SQL.
- A parameter never stands for a name (a domain, field, metric or unit), and not yet
  for `LIMIT` or a list.
