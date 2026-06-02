-- =====================================================================
-- Query Validation Checks — data & detection sanity assertions
-- =====================================================================
-- Lightweight assertions to run after loading sample data and the
-- harness. Each query should return ZERO rows (a returned row = a failed
-- check). Wire these into CI or a dbt test suite as you grow the pack.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

-- CHECK 1: every transaction references an existing account (no orphans)
SELECT 'orphan_transaction' AS check_name, t.transaction_id
FROM FRAUD.TRANSACTIONS t
LEFT JOIN FRAUD.ACCOUNTS a ON a.account_id = t.account_id
WHERE a.account_id IS NULL;

-- CHECK 2: every label references an existing transaction
SELECT 'orphan_label' AS check_name, l.transaction_id
FROM FRAUD.FRAUD_LABELS l
LEFT JOIN FRAUD.TRANSACTIONS t ON t.transaction_id = l.transaction_id
WHERE t.transaction_id IS NULL;

-- CHECK 3: no negative or null transaction amounts
SELECT 'bad_amount' AS check_name, transaction_id
FROM FRAUD.TRANSACTIONS
WHERE transaction_amount IS NULL OR transaction_amount < 0;

-- CHECK 4: detection results must reference real transactions
SELECT 'orphan_detection' AS check_name, d.transaction_id
FROM FRAUD.DETECTION_RESULTS d
LEFT JOIN FRAUD.TRANSACTIONS t ON t.transaction_id = d.transaction_id
WHERE t.transaction_id IS NULL;

-- CHECK 5: card-testing rule must catch at least one known seeded ring.
-- (Returns a row ONLY if the rule found nothing — i.e. a regression.)
SELECT 'card_testing_no_hits' AS check_name, 'CARD_TESTING' AS detection_rule
WHERE NOT EXISTS (
    SELECT 1 FROM FRAUD.DETECTION_RESULTS WHERE detection_rule = 'CARD_TESTING'
);

-- CHECK 6: overall recall on labeled fraud should not collapse to 0.
SELECT 'zero_recall' AS check_name, COUNT(*) AS labeled_fraud
FROM FRAUD.FRAUD_LABELS l
WHERE l.is_confirmed_fraud
  AND NOT EXISTS (SELECT 1 FROM FRAUD.DETECTION_RESULTS d
                  WHERE d.transaction_id = l.transaction_id)
HAVING COUNT(*) = (SELECT COUNT(*) FROM FRAUD.FRAUD_LABELS WHERE is_confirmed_fraud);
