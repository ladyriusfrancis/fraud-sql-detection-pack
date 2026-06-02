-- =====================================================================
-- 06 — Precision / Recall Monitoring
-- =====================================================================
-- Purpose: a single, schedulable monitoring query that reports the live
-- precision, recall, and false-positive rate of every detection rule
-- against confirmed-fraud labels. Run it on a schedule (e.g. daily) to
-- watch for rule decay as fraud patterns shift.
--
-- Contract: detections are materialized at TRANSACTION grain into
-- FRAUD.DETECTION_RESULTS(transaction_id, detection_rule, risk_score,
-- scored_at). The evaluation/ harness shows how to populate this table
-- by expanding each rule's flagged entities to their transactions.
--
-- Universe: all transactions are candidates. A transaction is a POSITIVE
-- prediction if it appears in DETECTION_RESULTS for the rule; it is an
-- actual fraud if FRAUD_LABELS.is_confirmed_fraud = TRUE. Transactions
-- absent from FRAUD_LABELS are treated as legitimate (true negatives).
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH labeled AS (
    SELECT
        t.transaction_id,
        COALESCE(l.is_confirmed_fraud, FALSE) AS actual_fraud
    FROM FRAUD.TRANSACTIONS t
    LEFT JOIN FRAUD.FRAUD_LABELS l ON l.transaction_id = t.transaction_id
),
rules AS (
    SELECT DISTINCT detection_rule FROM FRAUD.DETECTION_RESULTS
),
-- One row per (rule, transaction): was it predicted positive by that rule?
predictions AS (
    SELECT
        r.detection_rule,
        lb.transaction_id,
        lb.actual_fraud,
        IFF(d.transaction_id IS NOT NULL, TRUE, FALSE) AS predicted_fraud
    FROM rules r
    CROSS JOIN labeled lb
    LEFT JOIN FRAUD.DETECTION_RESULTS d
        ON d.transaction_id = lb.transaction_id
       AND d.detection_rule = r.detection_rule
),
confusion AS (
    SELECT
        detection_rule,
        SUM(IFF(predicted_fraud AND actual_fraud, 1, 0))           AS tp,
        SUM(IFF(predicted_fraud AND NOT actual_fraud, 1, 0))       AS fp,
        SUM(IFF(NOT predicted_fraud AND actual_fraud, 1, 0))       AS fn,
        SUM(IFF(NOT predicted_fraud AND NOT actual_fraud, 1, 0))   AS tn
    FROM predictions
    GROUP BY detection_rule
)
SELECT
    detection_rule,
    tp, fp, fn, tn,
    tp + fp                                          AS total_flagged,
    tp + fn                                          AS total_actual_fraud,
    ROUND(tp / NULLIF(tp + fp, 0), 4)                AS precision,
    ROUND(tp / NULLIF(tp + fn, 0), 4)                AS recall,
    ROUND(fp / NULLIF(fp + tn, 0), 4)                AS false_positive_rate,
    ROUND(2.0 * tp / NULLIF(2 * tp + fp + fn, 0), 4) AS f1_score,
    CURRENT_TIMESTAMP()                              AS evaluated_at
FROM confusion
ORDER BY detection_rule;
