-- =====================================================================
-- 03 — Merchant Abuse Pattern
-- =====================================================================
-- Typology: A merchant (or merchant account used as a fraud conduit)
-- shows an abnormal authorization profile vs. its peers — most tellingly
-- a decline rate far above the population. Catches bust-out merchants
-- and laundering conduits.
--
-- Detection logic: build a daily per-merchant profile, then score each
-- merchant-day's decline rate with a ROBUST z-score (median + MAD)
-- instead of mean/stddev. The robust statistic resists contamination
-- from a handful of other bad merchants in the population, which would
-- otherwise inflate the mean/stddev and hide true outliers. Flag
-- merchant-days clearing a minimum volume whose robust z >= threshold.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH params AS (
    SELECT
        3.5     AS robust_z_threshold,  -- modified z-score cutoff
        15      AS min_daily_attempts,  -- ignore low-volume noise
        0.40    AS min_decline_rate
),
daily_merchant AS (
    SELECT
        merchant_id,
        DATE_TRUNC('day', created_at)                  AS activity_day,
        COUNT(*)                                        AS attempts,
        COUNT(DISTINCT account_id)                      AS distinct_accounts,
        COUNT(DISTINCT card_fingerprint)               AS distinct_cards,
        SUM(IFF(auth_result = 'DECLINED', 1, 0))       AS declines,
        SUM(IFF(auth_result = 'DECLINED', 1, 0)) / NULLIF(COUNT(*),0) AS decline_rate,
        SUM(transaction_amount)                         AS gross_amount
    FROM FRAUD.TRANSACTIONS
    WHERE merchant_id IS NOT NULL
    GROUP BY 1, 2
),
eligible AS (
    SELECT dm.* FROM daily_merchant dm
    CROSS JOIN params p
    WHERE dm.attempts >= p.min_daily_attempts
),
pop_median AS (
    -- pass 1: population median decline rate over eligible merchant-days
    SELECT MEDIAN(decline_rate) AS med_dr FROM eligible
),
robust_stats AS (
    -- pass 2: MAD = median absolute deviation from the median
    SELECT
        pm.med_dr                                   AS med_dr,
        MEDIAN(ABS(e.decline_rate - pm.med_dr))     AS mad_dr
    FROM eligible e
    CROSS JOIN pop_median pm
    GROUP BY pm.med_dr
)
SELECT
    e.merchant_id,
    e.activity_day,
    e.attempts,
    e.distinct_accounts,
    e.distinct_cards,
    e.decline_rate,
    e.gross_amount,
    rs.med_dr                                              AS population_median_decline,
    ROUND(0.6745 * (e.decline_rate - rs.med_dr)
          / NULLIF(rs.mad_dr, 0), 3)                       AS robust_decline_zscore,
    ROUND(LEAST(0.6745 * (e.decline_rate - rs.med_dr)
          / NULLIF(rs.mad_dr, 0) / 7.0, 1), 3)             AS risk_score,
    'MERCHANT_ABUSE' AS detection_rule
FROM eligible e
CROSS JOIN params p
CROSS JOIN robust_stats rs
WHERE e.decline_rate >= p.min_decline_rate
  AND 0.6745 * (e.decline_rate - rs.med_dr)
        / NULLIF(rs.mad_dr, 0) >= p.robust_z_threshold
ORDER BY robust_decline_zscore DESC;
