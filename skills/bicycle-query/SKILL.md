---
name: bicycle-query
description: Answer business questions through Bicycle Studio's query tools using the model's advertised SQL language. Covers totals, rankings, trends and comparisons, preserves consent requests and warnings, and checks names and query capabilities before running.
---

# Query Bicycle data

Use the bundled Bicycle AI MCP connection and its `query_*` tools. Resolve the tools
by their actual client names; the namespace prefix differs between clients. If
disconnected, direct the user to add or connect Bicycle AI in the plugin's Connectors
tab in Claude chat or Cowork, or use the client's MCP authentication flow in Claude
Code or Codex. Never ask for credentials in chat or switch identities.

| Tool | Use it to |
|---|---|
| `query_list_models` | List accessible models and their SQL language; use the exact `model` identifier |
| `query_describe_model` | Read exact metric columns, fields, availability, time column and SQL hint |
| `query_describe_metric` | Read one metric's definition and the dimensions it can be sliced by |
| `query_search_fields` | Find the exact field name for words like "by country" |
| `query_dimension_values` | Get literal values for a filter (may ask for consent, see below) |
| `query_compile` / `query_explain` | Check a statement without running it: issues, route, price |
| `query_run` | Run the statement and get rows |

## Workflow

1. **Describe.** Call `query_list_models` and read its **SQL language** column.
   Semantic SQL (v2) uses `MEASURE(metric)`; Studio SQL (v1) uses metric columns.
   If the list has no language column, use the SQL hint and columns from describe.
   The same server can expose both languages. Never switch the tenant's routing
   setting or retry a refused query in another language.
   Use the only domain, or the one the user
   named; otherwise pick the domain whose description and vocabulary match the
   question and whose metrics are available (`from`/`till` in `query_describe_model`)
   for the dates asked about. Ask when several still fit. With no domains, say onboarding is needed. Do not
   import, sync or create anything. Call `query_describe_model` for the chosen
   `model`. Use `query_describe_metric` when the definition matters, and
   `query_search_fields` for every field you intend to use. Reuse what you learned
   on follow-up questions.
2. **Write the SQL in that model's language.** For Studio SQL, follow
   [Studio SQL](references/studio-sql.md); its grammar, parameters, cache rules and
   result handling differ from v2. For v2, use the semantic SQL rules below,
   [grammar](references/grammar.md) and [examples.sql](references/examples.sql).
   Copy the described `FROM` spelling; quote digit-leading or punctuated model
   identifiers with double quotes, such as `FROM "0example_model"`.
3. **Check the plan** with `query_explain` (or `query_compile`) when the statement is
   new or composed, when the user asks for a preview, or when cost may matter. It
   shows issues, whether the cache or the warehouse answers, and the estimated price.
   Fix compile or plan issues before execution. A plan is not data, and a price in
   a plan is information, not a consent question: go on to `query_run`.
4. **Run** with `query_run`, passing the same `model`, `sql` and `params`. It fetches
   up to `max_rows` rows (default 200, at most 50,000) and shows the first
   `show_rows` of them (default 50, at most 200). Raise `show_rows` when needed and
   do not claim to have inspected rows beyond the displayed table.
5. **Consent.** Only a `query_run` (or `query_dimension_values`) answer that starts
   with **Consent needed; nothing ran.** is a consent question. Then stop.
   Relay the estimated price and the choice to the user. Only after the user agrees,
   call `query_run` again with the same `sql` and `params` plus the `consent` it
   names. See [Consent](#consent).
6. **Report** the answer with its warnings, truncation and default-window notes
   (see [Reading the result](#reading-the-result)).
7. **Fix from teaching errors.** An error starts with its code, such as
   `NOT_GROUPED: …`. Look the code up in the [error table](references/errors.md),
   apply that fix, and keep the user's intent. Use `did_you_mean` suggestions only
   when they mean what the user asked. If the same fix fails twice, report the error
   to the user instead of looping or weakening the question.

The following language, consent, rollup and computation details apply to v2.
Use the Studio SQL reference for a v1 model.

## Semantic SQL rules

- `FROM <domain>` names the domain (the `model` from `query_list_models`). It is
  never joined or aliased; compose several selects through CTEs.
- `MEASURE(metric)` is the only way to read a metric: `MEASURE(revenue)`. Not
  `SUM(orders.amount)`, not `AGG(revenue)`, not a bare `revenue`.
- Fields are `dataset.field` (`orders.region`). The model picks the join path. Do not
  write JOINs to the domain or invent fields that describe did not show.
- `time` is each metric's event time. The window is half-open:
  `WHERE time >= <from> AND time < <to>`. Each bound is a literal (`'2026-09-01'`), a
  `:param`, or `CURRENT_DATE` / `CURRENT_TIMESTAMP` with an optional
  `- INTERVAL 'n' DAY`. BETWEEN and other forms of time filter are refused.
- **The reporting zone.** `query_run`, `query_compile` and `query_explain` take an
  optional `timezone` (an IANA name, e.g. `America/New_York`). Buckets, bare bounds,
  bare filter values, `CURRENT_DATE` and default windows are all read in that zone —
  the domain's own zone if you omit it, else UTC. Pass `timezone` when the user's
  question names a region or clock ("in IST", "New York time"); otherwise let the
  domain default apply and tell the user which zone was used, from the `{zone,
  source}` the answer discloses. An offset written on a bound
  (`2026-09-01T00:00:00+05:30`) fixes that moment but never sets the reporting zone.
  Time buckets and timestamps come back with their offset
  (`2026-01-01T09:00:00+05:30`) — quote them exactly as given.
- **Time axes and grains.** The engine checks a metric's time axis and supported
  grains. Studio's metric card may omit that detail; use `query_explain` to check
  a new bucket and use the supported grains in an engine refusal.
  `DATE_TRUNC(g, time) AS <alias>` grains are `minute`, `hour`, `day`, `week` (weeks
  start Monday), `month`, `quarter` and `year`. For 5, 15 or 30 minutes, or 3, 6 or 12
  hours, write `TIME_BUCKET(INTERVAL '30' MINUTE, time) AS bucket`. Those are the
  only sub-day sizes (the ladder 1m → 5m → 15m → 30m → 1h → 3h → 6h → 12h → 1d → 1w);
  for any other size, say so and offer the nearest rung. Alias the bucket (`bucket`,
  `hour`, `day`, `week`, `month`, `quarter`, `year`) and order by that alias. A `Date`
  axis floors at `day` and cannot be bucketed below it: asking for `hour` or finer is
  `GRAIN_NOT_SUPPORTED`, naming the axis, its datatype, its floor and the supported
  grains — pick one of those instead. A bound finer than a day-floor axis is snapped
  outward to the day, and the disclosure shows `snapped: true`; tell the user the
  window that was actually used, not the one asked for. Never substitute 30 days or
  derive months from day buckets with string functions now that `month`, `quarter`
  and `year` are grains.
- `GROUP BY ALL` (or list every field you select). A condition on a measure goes in
  `HAVING`, or in `QUALIFY` for a window function; never in `WHERE`.
- Outside the semantic selects, ordinary SQL works over their results: CTEs, joins
  between CTEs, window functions, `QUALIFY`, arithmetic, `COALESCE`, `NULLIF`,
  `CASE`, `ORDER BY`, `LIMIT`. Summing or averaging a ratio, average or distinct
  count across groups is refused; ask for it at the grouping you need instead.
- Period-over-period: two semantic selects with different windows in CTEs, joined
  with `FULL OUTER JOIN` on the dimension. There is no compare keyword.
- A select with no `MEASURE` is a row select. It returns rows (or distinct values
  with `SELECT DISTINCT`), always runs on the warehouse, and may need consent. Never
  re-aggregate a row select to rebuild a metric; read the metric with `MEASURE`.
- Return full precision. No `ROUND`, `CAST` to text or other formatting in the SQL;
  round only when you write the answer.
- Values the user supplies go in `params` as `:name`, never pasted into the text.
  Declare time parameters with a type: `{"since": {"type": "timestamp", "value":
  "2026-09-01"}}`. A bare JSON string is a string, and comparing it with `time` is
  refused. Parameter names may not be SQL keywords: use `:since` and `:until`, not
  `:from` and `:to`, even if a tool hint shows them.
- `LIMIT` must stay within the domain's row limit. There is no pagination.

## Interpreting the question

- Use Bicycle's canonical terms exactly: `metric`, `dimension`, `field`, `filter`,
  `domain`, `dataset`, `reporting period`, and `date range`. When you talk to the
  user, call a metric a metric, never a "KPI", "indicator" or "measure". `MEASURE()`
  is only the SQL function that reads a metric; keep that word inside SQL. If the
  user uses a noncanonical term, interpret it and answer with the canonical term.
- Every query must include a time range. If the user gives none, use the last 7 whole
  days, `time >= CURRENT_DATE - INTERVAL '7' DAY AND time < CURRENT_DATE`, and
  disclose that the last 7 days were selected by default. Do not invent a business
  period such as "this year". Ask when a calendar period is ambiguous.
- Match the user's words against metric names, display names, descriptions and
  units. When two metrics could fit (`sales_price` and `sales_amount`), read
  `query_describe_metric` for each and pick the one whose definition matches the
  question's wording ("extended price", "net of discount"); say which you used. Ask
  when plausible metrics would still give materially different answers.
- The user's dates are fixed. On an empty result, check the metric's availability in
  `query_describe_model` and the domain choice; never move the window to where some
  data happens to be. Report an empty result as empty.
- Group only by dimensions every requested metric can be sliced by
  (`query_describe_metric`). For top N, order the metric descending and `LIMIT N`.
  For follow-ups, keep the earlier domain, window and filters unless told otherwise.

## Consent

`query_run` never spends without a person's yes. When the warehouse would cost money,
or a cube is stale, the tool answers with a consent question instead of rows: the
engine code, the **estimated price**, and the consent that clears it.

Ask the user only when `query_run` (or `query_dimension_values`) returns **Consent
needed; nothing ran.** A price, cost class or "served from warehouse" in
`query_compile` or `query_explain` output is never a reason to ask: it is an estimate,
and the plan's `consent?` column says whether a gate applies. Run the query; the gate,
if there is one, will ask.

- Tell the user what it would cost (quote the price as given, including "not
  available") and what choice they have. An ordinary data question is not approval.
- Only after the user agrees, repeat the same call with `consent: {"warehouse": true}`
  or `consent: {"stale": true}`, whichever the user chose. Never add consent on your
  own, and never carry an approval over to a different statement.
- `stale` uses the cube as it is; `warehouse` reads live data and may cost the price.
  A request for fresh data is not approval of stale data.
- Set `cache_only: true` when the user wants cached data only. A refusal
  (`CACHE_CANNOT_SERVE`) is the answer then; do not fall back to the warehouse.
- `query_dimension_values` and row selects read the warehouse and may ask too. If
  `query_dimension_values` fails, list the values with a `SELECT DISTINCT` row
  select instead (see `distinct-values` in the examples).

## Reading the result

`query_run` returns a markdown table and a footer: row count, where the answer was
served from, freshness, and any notes. Match values by column name.

- **Warnings** are listed under the table. A `RENAMED` warning ("`old` is now `new` —
  update saved queries") means a former name still resolved: answer normally and tell
  the user to update any saved query or report that uses the old name.
- **Truncation** can happen at fetch or display limits; say the result is incomplete and
  never present totals, shares or rankings from partial rows as complete.
  - `truncated at max_rows=N` is Studio's cut: the engine returned more rows than
    `max_rows`. Re-run with a larger `max_rows` (the table still shows at most 200
    rows), or aggregate in SQL.
  - If the table displays fewer rows than the footer fetched, increase `show_rows`
    (at most 200) before interpreting unseen rows. The engine refuses an answer
    over its ceiling with `RESULT_TOO_LARGE`; narrow or aggregate the statement.
    Do not report a refused answer as partial data.
- **Default window**: a "default window applied" note means the statement named no
  window; the domain's default (`last_7d`) is now 6 whole days plus today so far,
  starting at local midnight in the reporting zone — not 7 full prior days. Report
  the window it actually used.
- **Cached answers ending at now**: when the window runs past the cube's last
  refresh, the freshness line says "includes data up to …" and the answer carries
  `cache_through`. Say so in plain terms, e.g. "numbers through 14:00; the last 37
  minutes aren't in the cache."
- A `WINDOW_NOT_APPLIED` warning means the default window did not bound that metric
  (it has no time field the default reaches). Mention it: the answer may not be
  limited to the window you expected.
- Before you answer, check: the last `query_run` is the answer itself, not a probe or
  a check, and returns exactly the requested columns and rows; a top-N question has
  `ORDER BY` the metric and `LIMIT N` with the N the user asked for.
- Lead with the answer and its unit, then the domain, window, filters and any
  limitations. Empty results, NULL and zero are different. Only interpret a missing
  count as zero when the tool explicitly explains that the backend returned no row
  for that count; disclose that interpretation. Other NULLs and failed queries stay
  missing. Do not claim causes from correlations. Query each domain separately and
  disclose differences in definitions before comparing domains.

## Combining rows yourself

Before totalling, averaging or otherwise combining result rows yourself — across time
buckets, regions or any other rows you already have from earlier calls — check that
metric's `rollup`: `query_describe_metric`'s "re-totals by" line, or the metric table
in `query_describe_model`. `query_run`, `query_compile` and `query_explain` never
show it.

Even with a combinable `rollup`, only combine rows yourself when both hold:

- You hold every row of the grouping — not cut by `LIMIT`, a top-N, `HAVING`,
  `QUALIFY`, or a truncation notice. If the rows were truncated or filtered short,
  re-query instead of combining what you have.
- The rows cover exactly the scope you want: the same filters and the same window.

- `sum`: add the rows.
- `min` / `max`: take the min or the max across the rows; do not add them.
- `components`: fetch both named metrics at the same grouping, filters and window as
  the rows, sum each across the full set of rows, then divide the numerator's total
  by the denominator's total. If either component can't be fetched at that grouping —
  the query errors with `FIELD_NOT_REACHABLE`, or a same-name fallback the ratio
  would need is blocked for that component — ask for the ratio at the coarser
  grouping instead. A ratio can sometimes reach a dimension through a same-name field
  that its components, asked for directly, cannot.
- `none`: do not combine the rows locally. Ask the engine again at the coarser
  grouping in a new `query_run`, using the reason it gives.

Never re-total a ratio, average, distinct count or percentile by summing or
averaging rows. This is the same rule `NON_ADDITIVE_REAGGREGATION` (see the
[error table](references/errors.md)) enforces inside one SQL statement; the rollup
is that rule for combining rows across separate calls, outside SQL.

## Showing how an answer was computed

`query_run`, `query_compile` and `query_explain` append a **How this was computed**
section to their output: the reference id, where it ran with freshness, the window
and its timezone, the metric definitions and their filters, and fenced blocks for the
semantic SQL, the warehouse query and, when the cache answered, the cache query.

Lead with the answer. Do not paste that section, or any SQL, unasked; offer it in one
short line, such as "Ask to see how this was computed."

When the user asks what query ran, how a number was computed, or disputes a number:

- Quote the **Warehouse query** block verbatim from the tool output — never
  rewritten, reformatted or re-derived from the semantic SQL.
- Give the reference id, the window with its timezone, the metric definitions and
  their filters, and whether it ran live or from cache, with freshness. An answer
  that ran on the warehouse is findable in the warehouse's own query history; on
  Snowflake and BigQuery the section also gives the warehouse's own query id. A
  cache answer, or one on local DuckDB, has no warehouse history entry — only the
  reference id.

A cached answer: say it came from the cache, as of when, and show both the **Cache
query** and the **Warehouse query** — the warehouse query computes this answer
live; it did not run, and it can differ when the cube is stale — say so, and quote
the freshness.

Before relaying a consent ask (see [Consent](#consent)), show the warehouse query
together with the price. When the ask offers `consent: {"warehouse": true}`, that
query is what will run once the user says yes.

Nothing to re-run: the record lives only in the tool output of that call, never
stored or re-derived. Never re-run a query just to show its SQL. Use the section
already returned; if it is no longer in context, say so and offer to re-run.
