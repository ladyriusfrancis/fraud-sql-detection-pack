-- =====================================================================
-- 01 — Card Testing Velocity
-- =====================================================================
-- Typology: Fraudsters validate stolen card numbers by firing many
-- small-amount authorizations across many distinct cards from a single
-- device/IP in a short window. Signature = high distinct-card count +
-- high decline rate + low amounts + tight time clustering.
--
-- Detection logic: per (device_id, ip_address) sliding 30-minute bucket,
-- flag entities whose distinct-card count and decline rate exceed
-- thresholds. Emits one row per flagged entity-window with a score.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- Tunable thresholds are surfaced as CTE constants at the top.
-- =====================================================================

WITH params AS (
    SELECT
        30      AS window_minutes,        -- velocity window
        8       AS min_distinct_cards,    -- distinct cards in window to flag
        0.50    AS min_decline_rate,      -- share of attempts declined
        5.00    AS max_avg_amount         -- testing uses tiny amounts
),
windowed AS (
    SELECT
        t.device_id,
        t.ip_address,
        -- bucket start: floor each txn to its window_minutes slot
        TIME_SLICE(t.created_at, (SELECT window_minutes FROM params), 'MINUTE') AS window_start,
        COUNT(*)                                              AS attempts,
        COUNT(DISTINCT t.card_fingerprint)                   AS distinct_cards,
        COUNT(DISTINCT t.account_id)                          AS distinct_accounts,
        SUM(IFF(t.auth_result = 'DECLINED', 1, 0))           AS declines,
        AVG(t.transaction_amount)                            AS avg_amount,
        MIN(t.created_at)                                     AS first_seen,
        MAX(t.created_at)                                     AS last_seen,
        ARRAY_AGG(t.transaction_id)                          AS transaction_ids
    FROM FRAUD.TRANSACTIONS t
    WHERE t.device_id IS NOT NULL
    GROUP BY 1, 2, 3
),
scored AS (
    SELECT
        w.*,
        w.declines / NULLIF(w.attempts, 0)                   AS decline_rate,
        -- composite score 0..1: weighted blend of the three signals
        ROUND(
            0.5 * LEAST(w.distinct_cards / 20.0, 1)
          + 0.3 * (w.declines / NULLIF(w.attempts, 0))
          + 0.2 * (1 - LEAST(w.avg_amount / 50.0, 1)),
        3)                                                    AS risk_score
    FROM windowed w
)
SELECT
    device_id,
    ip_address,
    window_start,
    attempts,
    distinct_cards,
    distinct_accounts,
    decline_rate,
    avg_amount,
    risk_score,
    first_seen,
    last_seen,
    transaction_ids,
    'CARD_TESTING' AS detection_rule
FROM scored
CROSS JOIN params p
WHERE distinct_cards >= p.min_distinct_cards
  AND decline_rate   >= p.min_decline_rate
  AND avg_amount     <= p.max_avg_amount
ORDER BY risk_score DESC, distinct_cards DESC;
