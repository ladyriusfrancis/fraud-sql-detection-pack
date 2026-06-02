# PostgreSQL Equivalents

The queries are written for Snowflake. To run them on PostgreSQL, apply
these substitutions.

## Functions & syntax

| Snowflake | PostgreSQL |
|-----------|------------|
| `IFF(cond, a, b)` | `CASE WHEN cond THEN a ELSE b END` |
| `TIME_SLICE(ts, 30, 'MINUTE')` | `date_bin('30 minutes', ts, TIMESTAMP '2000-01-01')` |
| `DATEADD('minute', n, ts)` | `ts + (n \|\| ' minutes')::interval` |
| `DATEDIFF('minute', a, b)` | `EXTRACT(EPOCH FROM (b - a)) / 60` |
| `DATE_TRUNC('day', ts)` | `date_trunc('day', ts)` (same) |
| `ARRAY_AGG(x)` | `array_agg(x)` (same) |
| `ARRAY_CONTAINS(v::VARIANT, arr)` | `v = ANY(arr)` |
| `MEDIAN(x)` | `percentile_cont(0.5) WITHIN GROUP (ORDER BY x)` |
| `STDDEV(x)` | `stddev_samp(x)` |
| `LATERAL FLATTEN(input => arr)` | `unnest(arr)` |

## time_slice / date_bin (rule 01)

`date_bin` requires PostgreSQL 14+. On older versions, floor manually:

```sql
to_timestamp(floor(extract(epoch FROM created_at) / 1800) * 1800)
```

## UNPIVOT (rule 04)

PostgreSQL has no `UNPIVOT`. Use a `UNION ALL`:

```sql
SELECT 'DEVICE' AS id_type, device_id AS id_value, account_id, transaction_id, created_at
FROM fraud.transactions WHERE device_id IS NOT NULL
UNION ALL
SELECT 'IP', ip_address, account_id, transaction_id, created_at
FROM fraud.transactions WHERE ip_address IS NOT NULL
```

## Rolling window (rule 05)

PostgreSQL supports `RANGE BETWEEN INTERVAL` with a timestamp `ORDER BY`:

```sql
SUM(transaction_amount) OVER (
  PARTITION BY account_id ORDER BY created_at
  RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
)
```

This is one of the few places Snowflake and Postgres agree directly.

## MEDIAN/MAD (rule 03)

Replace `MEDIAN(x)` with
`percentile_cont(0.5) WITHIN GROUP (ORDER BY x)`, computed in two stages as
in the Snowflake version (median, then median of absolute deviations).
