# BigQuery Equivalents

The queries are written for Snowflake. To run them on BigQuery Standard SQL,
apply these substitutions.

## Functions & syntax

| Snowflake | BigQuery |
|-----------|----------|
| `IFF(cond, a, b)` | `IF(cond, a, b)` |
| `NVL` / `IFNULL` | `IFNULL` (or `COALESCE`) |
| `TIME_SLICE(ts, 30, 'MINUTE')` | `TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(ts), 1800) * 1800)` |
| `DATEADD('minute', n, ts)` | `TIMESTAMP_ADD(ts, INTERVAL n MINUTE)` |
| `DATEDIFF('minute', a, b)` | `TIMESTAMP_DIFF(b, a, MINUTE)` |
| `DATE_TRUNC('day', ts)` | `TIMESTAMP_TRUNC(ts, DAY)` |
| `ARRAY_AGG(x)` | `ARRAY_AGG(x)` (same) |
| `ARRAY_CONTAINS(v::VARIANT, arr)` | `value IN UNNEST(arr)` |
| `MEDIAN(x)` | `APPROX_QUANTILES(x, 2)[OFFSET(1)]` |
| `STDDEV(x)` | `STDDEV(x)` (same) |
| `LATERAL FLATTEN(input => arr)` | `UNNEST(arr)` |

## UNPIVOT (rule 04)

BigQuery supports `UNPIVOT`:

```sql
SELECT id_type, id_value, account_id, transaction_id, created_at
FROM FRAUD.TRANSACTIONS
UNPIVOT (id_value FOR id_type IN (device_id AS 'DEVICE', ip_address AS 'IP'))
```

If your column types differ, cast both to STRING first, or use a `UNION ALL`
of two `SELECT`s as a portable fallback.

## Rolling window (rule 05)

BigQuery does not support `RANGE BETWEEN INTERVAL '24 hours' PRECEDING`.
Use a self-join or a range over a unix-seconds expression:

```sql
SUM(transaction_amount) OVER (
  PARTITION BY account_id
  ORDER BY UNIX_SECONDS(created_at)
  RANGE BETWEEN 86400 PRECEDING AND CURRENT ROW
)
```

## MEDIAN/MAD (rule 03)

Replace `MEDIAN(x)` with `APPROX_QUANTILES(x, 2)[OFFSET(1)]`. Compute the
MAD in two stages exactly as the Snowflake version does (median first, then
median of absolute deviations).
