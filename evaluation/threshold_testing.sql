-- =====================================================================
-- Threshold Testing — precision/recall trade-off sweep
-- =====================================================================
-- Sweeps a risk_score cutoff across DETECTION_RESULTS and reports how
-- precision, recall, and F1 move as the cutoff tightens. Use this to
-- pick an operating point per the precision/recall framework in docs/.
--
-- Output: one row per threshold step with the resulting metrics so you
-- can plot the PR curve or pick the knee.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH thresholds AS (
    -- candidate cutoffs 0.0, 0.1, ... 0.9
    SELECT seq AS threshold
    FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n
          FROM TABLE(GENERATOR(ROWCOUNT => 10))), LATERAL (SELECT n/10.0 AS seq)
),
labeled AS (
    SELECT t.transaction_id,
           COALESCE(l.is_confirmed_fraud, FALSE) AS actual_fraud
    FROM FRAUD.TRANSACTIONS t
    LEFT JOIN FRAUD.FRAUD_LABELS l ON l.transaction_id = t.transaction_id
),
-- best (max) score per transaction across all rules
scored AS (
    SELECT transaction_id, MAX(risk_score) AS best_score
    FROM FRAUD.DETECTION_RESULTS
    GROUP BY transaction_id
),
joined AS (
    SELECT lb.transaction_id, lb.actual_fraud,
           COALESCE(s.best_score, -1) AS best_score
    FROM labeled lb
    LEFT JOIN scored s ON s.transaction_id = lb.transaction_id
)
SELECT
    th.threshold,
    SUM(IFF(j.best_score >= th.threshold AND j.actual_fraud, 1, 0))       AS tp,
    SUM(IFF(j.best_score >= th.threshold AND NOT j.actual_fraud, 1, 0))   AS fp,
    SUM(IFF(j.best_score <  th.threshold AND j.actual_fraud, 1, 0))       AS fn,
    ROUND(SUM(IFF(j.best_score >= th.threshold AND j.actual_fraud,1,0))
        / NULLIF(SUM(IFF(j.best_score >= th.threshold,1,0)),0), 4)        AS precision,
    ROUND(SUM(IFF(j.best_score >= th.threshold AND j.actual_fraud,1,0))
        / NULLIF(SUM(IFF(j.actual_fraud,1,0)),0), 4)                      AS recall
FROM thresholds th
CROSS JOIN joined j
GROUP BY th.threshold
ORDER BY th.threshold;
