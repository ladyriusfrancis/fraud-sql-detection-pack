-- =====================================================================
-- 04 — Anomalous Cluster Detection (shared-identifier rings)
-- =====================================================================
-- Typology: Organized fraud rings reuse infrastructure — the same
-- device_id or ip_address spans many otherwise-unrelated accounts.
-- A single device touching many accounts in a short period is a strong
-- linkage signal for mule networks and bonus/promo abuse rings.
--
-- Detection logic: treat each shared identifier (device_id, ip_address)
-- as a candidate cluster node. Count distinct accounts linked to it,
-- and flag clusters whose fan-out exceeds a threshold. Output includes
-- the linked account set so an analyst can pivot directly into a case.
--
-- This is a graph/clustering-style heuristic expressed in pure SQL: the
-- shared identifier is the cluster key; account fan-out is the density.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH params AS (
    SELECT
        4       AS min_accounts_per_identifier,  -- fan-out to flag
        7       AS lookback_days
),
identifier_links AS (
    -- Unpivot device_id and ip_address into a single (id_type, id_value) grain.
    SELECT id_type, id_value, account_id, transaction_id, created_at
    FROM FRAUD.TRANSACTIONS
    UNPIVOT (id_value FOR id_type IN (device_id AS 'DEVICE', ip_address AS 'IP'))
    WHERE id_value IS NOT NULL
),
recent AS (
    SELECT *
    FROM identifier_links
    -- Anchor lookback to the latest event in the dataset for portability.
    WHERE created_at >= DATEADD('day', -(SELECT lookback_days FROM params),
                                (SELECT MAX(created_at) FROM FRAUD.TRANSACTIONS))
),
clusters AS (
    SELECT
        id_type,
        id_value,
        COUNT(DISTINCT account_id)         AS distinct_accounts,
        COUNT(DISTINCT transaction_id)     AS txn_count,
        ARRAY_AGG(DISTINCT account_id)     AS linked_accounts,
        MIN(created_at)                     AS first_seen,
        MAX(created_at)                     AS last_seen
    FROM recent
    GROUP BY 1, 2
)
SELECT
    id_type,
    id_value                                              AS shared_identifier,
    distinct_accounts,
    txn_count,
    linked_accounts,
    first_seen,
    last_seen,
    ROUND(LEAST(distinct_accounts / 10.0, 1), 3)          AS risk_score,
    'ANOMALOUS_CLUSTER' AS detection_rule
FROM clusters
CROSS JOIN params p
WHERE distinct_accounts >= p.min_accounts_per_identifier
ORDER BY distinct_accounts DESC, txn_count DESC;
