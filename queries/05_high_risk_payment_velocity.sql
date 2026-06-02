-- =====================================================================
-- 05 — High-Risk Payment Velocity (per-account spend bursts)
-- =====================================================================
-- Typology: A compromised or bust-out account suddenly transacts far
-- faster and larger than normal — a rolling burst of approved spend in a
-- short window. Complements ATO by catching bust-outs with no clean
-- login signal.
--
-- Detection logic: a window function computes each account's rolling
-- 24-hour approved transaction COUNT and total SPEND. Flag rows where
-- the rolling count clears a minimum AND rolling spend clears an
-- absolute spend floor. We deliberately use an absolute spend floor
-- (a tunable, currency-specific amount) rather than a self-relative
-- multiple, because a bust-out inflates the account's own average and
-- makes self-relative baselines unstable. KYC / high-risk-segment
-- signals feed the score but not the gate.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH params AS (
    SELECT
        5       AS min_window_txns,   -- rolling 24h approved count
        2000.00 AS spend_floor        -- absolute rolling 24h spend (USD)
),
approved AS (
    SELECT t.*, a.kyc_status, a.is_high_risk_segment
    FROM FRAUD.TRANSACTIONS t
    JOIN FRAUD.ACCOUNTS a ON a.account_id = t.account_id
    WHERE t.auth_result = 'APPROVED'
),
rolling AS (
    SELECT
        account_id,
        transaction_id,
        created_at,
        transaction_amount,
        kyc_status,
        is_high_risk_segment,
        SUM(transaction_amount) OVER (
            PARTITION BY account_id ORDER BY created_at
            RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
        ) AS rolling_24h_spend,
        COUNT(*) OVER (
            PARTITION BY account_id ORDER BY created_at
            RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
        ) AS rolling_24h_txns
    FROM approved
)
SELECT
    account_id,
    transaction_id,
    created_at,
    transaction_amount,
    rolling_24h_spend,
    rolling_24h_txns,
    kyc_status,
    is_high_risk_segment,
    ROUND(
        0.4 * LEAST(rolling_24h_spend / 10000.0, 1)
      + 0.3 * IFF(is_high_risk_segment, 1, 0)
      + 0.3 * IFF(kyc_status <> 'VERIFIED', 1, 0),
    3) AS risk_score,
    'HIGH_RISK_VELOCITY' AS detection_rule
FROM rolling
CROSS JOIN params p
WHERE rolling_24h_txns  >= p.min_window_txns
  AND rolling_24h_spend >= p.spend_floor
ORDER BY risk_score DESC, rolling_24h_spend DESC;
