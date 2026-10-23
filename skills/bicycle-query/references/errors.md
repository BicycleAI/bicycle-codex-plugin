# Teaching errors and their fixes

These are semantic SQL (v2) codes. Studio SQL (v1) has different compile issues;
see [Studio SQL](studio-sql.md). Relay errors without changing the model's language.

The engine refuses a statement with a code and a message that names the problem.
`query_compile` and `query_explain` list them as issues; `query_run` returns them as
an error beginning with the code. Many carry extra material: `did_you_mean` (closest
names), `keys` (the current group keys), `supported` (grains), `maximum` (a limit).
These details come with `query_run` errors and may not appear in the issue tables of
`query_compile` and `query_explain`; when you need them, run the statement.
Fix the statement as the table says, keep the user's intent, and re-check it.

## Language

| Code | What it means | Fix |
|---|---|---|
| `SQL_SYNTAX` | The text does not parse; `line` and `column` point at the spot. | Correct the SQL there. A `:name` that opens a select item is read as an alias: write `0 + :k AS k`, or move the parameter to `WHERE`. |
| `SQL_NOT_ALLOWED` | A construct outside the language: `MEDIAN`, `FILTER (WHERE …)`, `OFFSET`, a subquery or CTE inside a semantic select, `*` from the domain, a physical table, a keyword as a parameter name (`:from`), `AGG()`, two statements, a size limit. `construct` names it. | Use the replacement the message gives: a declared metric for medians and percentiles, `SUM(CASE WHEN …)` for `FILTER`, a CTE for composition, `:since`/`:until` for parameter names. |
| `MEASURE_MISUSE` | A metric read the wrong way: a bare metric name, `SUM(dataset.field)` or another raw aggregate, `MEASURE` in `WHERE` or `GROUP BY`, or `MEASURE(x)` over a CTE instead of the domain. | Write `MEASURE(metric)` with a bare name from describe, inside a select `FROM <domain>`. Over a CTE, read the column the measure was aliased to (`rev`, not `MEASURE(rev)`). Move a condition on a measure to `HAVING`. If no declared metric fits, tell the user; do not aggregate fields yourself. |
| `NOT_GROUPED` | A field is selected or ordered but is not a group key. `keys` lists the current ones. | Add it to `GROUP BY`, or use `GROUP BY ALL`. |
| `FILTER_NOT_PUSHABLE` | A `WHERE` condition the filter grammar cannot express, such as `LIKE`, a function on a field or a comparison of two fields. | Compare `dataset.field` with values (`=`, `IN`, `BETWEEN`, `IS NULL`, `CONTAINS`). Compute anything else over the results in an outer select. |
| `TIME_FILTER_FORM` | The time filter is not `time >= a AND time < b` at the top level of `WHERE`: `BETWEEN`, `<=` at the end, a single bound (both ends are required), a time bound under `OR` or `NOT`, or an empty window. | Write the half-open window with both ends, joined to the other conditions by `AND`. For an inclusive end date, use the next day as the exclusive end; for "until now", end at `time < CURRENT_TIMESTAMP`. |
| `GRAIN_NOT_SUPPORTED` | A `TIME_BUCKET` size off the ladder (e.g. 20 minutes, 2 hours), or a `DATE_TRUNC` grain finer than the axis's floor — `'hour'` against a `Date` axis. The detail names the axis, its `datatype`, its `floor` and the `supported` grains (and `nearest` rungs, for a `TIME_BUCKET` miss). | Use a ladder size: `TIME_BUCKET(INTERVAL 'N' MINUTE\|HOUR, time)` for 5/15/30 minutes or 3/6/12 hours, offering the nearest rung. Against a day-floor axis, pick one of the `supported` grains (`day`, `week`, `month`, `quarter`, `year`) instead of an hour or finer — read them from the error or from `query_describe_metric`'s `time_axis`. |
| `AXIS_KIND_INVALID` | The model's time axis is misdeclared — its `kind` does not match the column it names. | Not a query fix: tell the user to ask the model owner to correct the field's declaration. Do not work around it in SQL. |
| `INVALID_QUERY` | `timezone` is not a valid IANA name. | Fix the `timezone` argument, or drop it; without it the domain's zone (else UTC) applies. |
| `NON_ADDITIVE_REAGGREGATION` | `SUM` or `AVG` over a ratio, average, distinct count, percentile or opaque metric. The result would not equal the metric. | Ask for the metric at the grouping you need in another semantic select, or re-aggregate its additive parts (numerator and denominator) and divide. |
| `UNBOUND_PARAMETER` | The SQL uses `:name` and `params` does not supply it. | Add it to `params` with its type. |
| `UNKNOWN_PARAMETER` | `params` supplies a name the SQL never uses. | Remove it, or use it in the SQL. |
| `TYPE_MISMATCH` | A value does not match its field or `time`: a bare string parameter compared with `time`, a number compared with a text field. | Declare time parameters as `{"type": "timestamp", "value": …}` (or `date`); use a value of the field's type. |
| `MULTIPLE_DOMAINS` | One statement reads two domains (or one domain under two of its names). | Ask each domain in its own statement; compare the answers in your reply. |
| `SQL_VENUE_REJECTED` | The composed outer SQL failed where it ran: an unknown CTE column, an ambiguous column, a type error. | Check the column names each CTE outputs (`orders.region` becomes `region`; aliases win) and qualify ambiguous ones with the CTE name. |
| `LIMIT_EXCEEDED` | `LIMIT` is above the effective maximum (`maximum`). | Lower the limit, or aggregate further. There is no pagination. |
| `VALUES_LIMIT` | A `SELECT DISTINCT` asks for more values than the listing cap. | Lower the limit, or narrow with a filter such as `CONTAINS`. |

## Names

| Code | What it means | Fix |
|---|---|---|
| `DOMAIN_REQUIRED` | The statement reads no domain. | Add `FROM <domain>` to the select that reads the model. |
| `UNKNOWN_DOMAIN` | `FROM` names no domain (a deleted one carries `retired`). | Use a `model` from `query_list_models`; check `did_you_mean`. |
| `UNKNOWN_METRIC` | No metric of that name in the domain, or a qualified name such as `MEASURE(orders.revenue)`. | Metric names are bare: `MEASURE(revenue)`. Pick from `did_you_mean` only when it means what the user asked; otherwise re-read `query_describe_model`. |
| `UNKNOWN_FIELD` | No such field on that dataset. | Use `query_search_fields` or `did_you_mean` for the exact `dataset.field`. |
| `UNKNOWN_DATASET` | The prefix of `dataset.field` is not a dataset of the domain. | Use a dataset listed by `query_describe_model`. |
| `FIELD_NOT_REACHABLE` | A metric cannot be sliced or filtered by that field; no to-one path joins them. Also raised for a stated time window over a metric with no time field. | Use a supported dimension. For an unreachable time window, explain that this metric cannot answer the requested period; do not silently drop the dates. |
| `AXIS_KIND_INVALID` | The model's stored time axis has an unsupported datatype. | Report the model problem to its owner; do not guess another time field. |
| `INVALID_QUERY` | A request argument is invalid; `field` may identify `timezone`. | Follow the message. A reporting zone is an IANA name such as `Asia/Kolkata`, never `IST` or `+05:30`. |
| `CROSS_CONNECTION_UNSUPPORTED` | The query spans more than one connection. | Query each supported scope separately and disclose the limitation; do not invent a cross-source join. |
| `RESULT_TOO_LARGE` | The engine refused the whole answer because it exceeds a row ceiling; `maximum` gives the limit. | Narrow or aggregate the statement, or use an intentional `ORDER BY … LIMIT` when the question permits it. There are no partial rows to report. |
| `QUERY_TOO_EXPENSIVE` | The estimated scan or warehouse bill exceeds the statement's budget. | Report the price and maximum, then narrow the question. Consent does not bypass this limit. |
| `TIMEOUT_TOO_LONG` | The requested timeout exceeds the platform's maximum. | Use the allowed bound or report the limit; do not split work to evade it. |

## Cache and consent

| Code | What it means | Fix |
|---|---|---|
| `CACHE_MISS_CONSENT_REQUIRED` | No cube serves the statement; the warehouse would answer it at the given price. | Relay the price. Rerun with `consent: {"warehouse": true}` only after the user agrees. |
| `STALE_CACHE_CONSENT_REQUIRED` | A cube can answer, but it is behind its refresh schedule. | Offer both choices: `{"stale": true}` uses the cube as it is, `{"warehouse": true}` reads live at the price. Rerun only with the user's choice. |
| `CACHE_CANNOT_SERVE` | `cache_only` was set and no cube serves every part. `reasons` says what is missing. | Report it. Do not drop `cache_only` unless the user agrees to a warehouse read. |
| `CACHE_MISS_REJECTED`, `GRAIN_TOO_FINE` | The metric is cache-only and no cube serves this shape, or the grain is finer than its cube. | Use a coarser grain or a dimension the cube carries (`query_describe_metric` lists cubes). Consent does not help. |

## Warnings (the query still answered)

| Warning | Meaning | What to tell the user |
|---|---|---|
| `RENAMED` | A former name of a domain or metric was used; it resolved to the current name. | Report the answer, and tell the user to update saved queries and reports from the old name to the new one. Use the new name yourself from now on. |
| Default window applied | The statement named no window, so the domain default was used. | Say which window the answer covers. |
| `truncated at max_rows=N` | Studio cut the engine's rows at `max_rows`. | Say the result is incomplete; re-run with a larger `max_rows` (up to 50,000 fetched; at most 200 shown), or aggregate in SQL. |
| `WINDOW_NOT_APPLIED` | The default window (no window stated) did not bound that metric — it has no time field the default reaches. | Mention it: the answer may not be limited to the window you expected. |

Authorization failures (401, 403) need the connection repaired, not a retry with
another tenant or tool. Do not retry a statement that failed the same way twice.
