-- =====================================================================
-- Confusion Matrix — overall and per-rule
-- =====================================================================
-- Produces the raw TP/FP/FN/TN cells for (a) the combined detection
-- system (a transaction is flagged if ANY rule fires) and (b) each rule
-- individually. Pair with precision_recall_harness.sql which populates
-- FRAUD.DETECTION_RESULTS.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH labeled AS (
    SELECT t.transaction_id,
           COALESCE(l.is_confirmed_fraud, FALSE) AS actual_fraud
    FROM FRAUD.TRANSACTIONS t
    LEFT JOIN FRAUD.FRAUD_LABELS l ON l.transaction_id = t.transaction_id
),
flagged_any AS (
    SELECT DISTINCT transaction_id FROM FRAUD.DETECTION_RESULTS
)
-- ---- Combined system confusion matrix ----
SELECT
    'ALL_RULES_COMBINED' AS scope,
    SUM(IFF(f.transaction_id IS NOT NULL AND lb.actual_fraud, 1, 0))         AS tp,
    SUM(IFF(f.transaction_id IS NOT NULL AND NOT lb.actual_fraud, 1, 0))     AS fp,
    SUM(IFF(f.transaction_id IS NULL AND lb.actual_fraud, 1, 0))             AS fn,
    SUM(IFF(f.transaction_id IS NULL AND NOT lb.actual_fraud, 1, 0))         AS tn
FROM labeled lb
LEFT JOIN flagged_any f ON f.transaction_id = lb.transaction_id

UNION ALL

-- ---- Per-rule confusion matrix ----
SELECT
    d.detection_rule AS scope,
    SUM(IFF(lb.actual_fraud, 1, 0))                                          AS tp,
    SUM(IFF(NOT lb.actual_fraud, 1, 0))                                      AS fp,
    NULL AS fn,   -- per-rule FN/TN require the full universe; see query 06
    NULL AS tn
FROM FRAUD.DETECTION_RESULTS d
JOIN labeled lb ON lb.transaction_id = d.transaction_id
GROUP BY d.detection_rule
ORDER BY scope;
