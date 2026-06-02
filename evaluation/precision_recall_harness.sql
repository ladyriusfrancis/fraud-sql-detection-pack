-- =====================================================================
-- Evaluation Harness — materialize detections, then score them
-- =====================================================================
-- This script (1) rebuilds FRAUD.DETECTION_RESULTS at TRANSACTION grain
-- by running each rule and expanding entity-level hits to transactions,
-- then (2) leaves scoring to queries/06_precision_recall_monitoring.sql.
--
-- Run order:
--   schema/snowflake_schema.sql  -> create tables & load data
--   evaluation/precision_recall_harness.sql  -> this file
--   queries/06_precision_recall_monitoring.sql  -> read metrics
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

CREATE OR REPLACE TABLE FRAUD.DETECTION_RESULTS (
    transaction_id  STRING,
    detection_rule  STRING,
    risk_score      FLOAT,
    scored_at       TIMESTAMP_NTZ
);

-- ---------------------------------------------------------------------
-- Rule 01 — Card testing: expand each flagged entity-window's txn array.
-- ---------------------------------------------------------------------
INSERT INTO FRAUD.DETECTION_RESULTS
WITH params AS (SELECT 30 AS window_minutes, 8 AS min_distinct_cards,
                       0.50 AS min_decline_rate, 5.00 AS max_avg_amount),
windowed AS (
    SELECT t.device_id, t.ip_address,
        TIME_SLICE(t.created_at,(SELECT window_minutes FROM params),'MINUTE') AS window_start,
        COUNT(*) AS attempts,
        COUNT(DISTINCT t.card_fingerprint) AS distinct_cards,
        SUM(IFF(t.auth_result='DECLINED',1,0)) AS declines,
        AVG(t.transaction_amount) AS avg_amount,
        ARRAY_AGG(t.transaction_id) AS transaction_ids
    FROM FRAUD.TRANSACTIONS t WHERE t.device_id IS NOT NULL GROUP BY 1,2,3
),
flagged AS (
    SELECT w.transaction_ids,
        0.5*LEAST(w.distinct_cards/20.0,1)+0.3*(w.declines/NULLIF(w.attempts,0))
        +0.2*(1-LEAST(w.avg_amount/50.0,1)) AS risk_score
    FROM windowed w CROSS JOIN params p
    WHERE w.distinct_cards>=p.min_distinct_cards
      AND w.declines/NULLIF(w.attempts,0)>=p.min_decline_rate
      AND w.avg_amount<=p.max_avg_amount
)
SELECT f.value::STRING, 'CARD_TESTING', flagged.risk_score, CURRENT_TIMESTAMP()
FROM flagged, LATERAL FLATTEN(input => flagged.transaction_ids) f;

-- ---------------------------------------------------------------------
-- Rule 02 — ATO: already at transaction grain (one txn per hit).
-- ---------------------------------------------------------------------
INSERT INTO FRAUD.DETECTION_RESULTS
WITH params AS (SELECT 60 AS payment_window_minutes, 30 AS failure_lookback_minutes,
                       3 AS min_recent_failures, 3.0 AS amount_multiplier),
account_history AS (
    SELECT account_id, ARRAY_AGG(DISTINCT country) AS known_countries,
           ARRAY_AGG(DISTINCT device_id) AS known_devices
    FROM FRAUD.LOGIN_EVENTS WHERE login_result='SUCCESS' GROUP BY account_id),
account_spend AS (
    SELECT account_id, AVG(transaction_amount) AS avg_amount
    FROM FRAUD.TRANSACTIONS WHERE auth_result='APPROVED' GROUP BY account_id),
recent_failures AS (
    SELECT s.login_id, COUNT(f.login_id) AS preceding_failures
    FROM FRAUD.LOGIN_EVENTS s
    LEFT JOIN FRAUD.LOGIN_EVENTS f ON f.account_id=s.account_id
        AND f.login_result='FAILURE' AND f.created_at<s.created_at
        AND f.created_at>=DATEADD('minute',-(SELECT failure_lookback_minutes FROM params),s.created_at)
    WHERE s.login_result='SUCCESS' GROUP BY s.login_id),
suspicious_logins AS (
    SELECT s.login_id,s.account_id,s.created_at AS login_at, rf.preceding_failures
    FROM FRAUD.LOGIN_EVENTS s
    JOIN account_history h ON h.account_id=s.account_id
    JOIN recent_failures rf ON rf.login_id=s.login_id
    CROSS JOIN params p
    WHERE s.login_result='SUCCESS' AND rf.preceding_failures>=p.min_recent_failures
      AND (NOT ARRAY_CONTAINS(s.country::VARIANT,h.known_countries)
        OR NOT ARRAY_CONTAINS(s.device_id::VARIANT,h.known_devices)))
SELECT t.transaction_id, 'ATO',
    0.4+0.3*LEAST(sl.preceding_failures/5.0,1)
    +0.3*LEAST(t.transaction_amount/NULLIF(sp.avg_amount,0)/5.0,1),
    CURRENT_TIMESTAMP()
FROM suspicious_logins sl CROSS JOIN params p
JOIN FRAUD.TRANSACTIONS t ON t.account_id=sl.account_id AND t.auth_result='APPROVED'
    AND t.created_at>=sl.login_at
    AND t.created_at<DATEADD('minute',p.payment_window_minutes,sl.login_at)
LEFT JOIN account_spend sp ON sp.account_id=sl.account_id
WHERE t.transaction_amount>=p.amount_multiplier*COALESCE(sp.avg_amount,0);

-- ---------------------------------------------------------------------
-- Rule 03 — Merchant abuse: expand flagged merchant-days to their txns.
-- ---------------------------------------------------------------------
INSERT INTO FRAUD.DETECTION_RESULTS
WITH params AS (SELECT 3.5 AS robust_z_threshold, 15 AS min_daily_attempts, 0.40 AS min_decline_rate),
daily_merchant AS (
    SELECT merchant_id, DATE_TRUNC('day',created_at) AS activity_day, COUNT(*) AS attempts,
        SUM(IFF(auth_result='DECLINED',1,0))/NULLIF(COUNT(*),0) AS decline_rate
    FROM FRAUD.TRANSACTIONS WHERE merchant_id IS NOT NULL GROUP BY 1,2),
eligible AS (SELECT dm.* FROM daily_merchant dm CROSS JOIN params p WHERE dm.attempts>=p.min_daily_attempts),
pop_median AS (SELECT MEDIAN(decline_rate) AS med_dr FROM eligible),
robust_stats AS (SELECT pm.med_dr, MEDIAN(ABS(e.decline_rate-pm.med_dr)) AS mad_dr
    FROM eligible e CROSS JOIN pop_median pm GROUP BY pm.med_dr),
flagged_md AS (
    SELECT e.merchant_id, e.activity_day,
        LEAST(0.6745*(e.decline_rate-rs.med_dr)/NULLIF(rs.mad_dr,0)/7.0,1) AS risk_score
    FROM eligible e CROSS JOIN params p CROSS JOIN robust_stats rs
    WHERE e.decline_rate>=p.min_decline_rate
      AND 0.6745*(e.decline_rate-rs.med_dr)/NULLIF(rs.mad_dr,0)>=p.robust_z_threshold)
SELECT t.transaction_id, 'MERCHANT_ABUSE', fm.risk_score, CURRENT_TIMESTAMP()
FROM flagged_md fm
JOIN FRAUD.TRANSACTIONS t ON t.merchant_id=fm.merchant_id
    AND DATE_TRUNC('day',t.created_at)=fm.activity_day;

-- ---------------------------------------------------------------------
-- Rule 04 — Anomalous cluster: expand flagged identifiers to their txns.
-- ---------------------------------------------------------------------
INSERT INTO FRAUD.DETECTION_RESULTS
WITH params AS (SELECT 4 AS min_accounts, 7 AS lookback_days),
links AS (
    SELECT id_type, id_value, account_id, transaction_id, created_at
    FROM FRAUD.TRANSACTIONS
    UNPIVOT (id_value FOR id_type IN (device_id AS 'DEVICE', ip_address AS 'IP'))
    WHERE id_value IS NOT NULL),
recent AS (
    SELECT * FROM links
    WHERE created_at>=DATEADD('day',-(SELECT lookback_days FROM params),
        (SELECT MAX(created_at) FROM FRAUD.TRANSACTIONS))),
flagged_ids AS (
    SELECT id_type, id_value, COUNT(DISTINCT account_id) AS acct,
        LEAST(COUNT(DISTINCT account_id)/10.0,1) AS risk_score
    FROM recent GROUP BY 1,2
    HAVING COUNT(DISTINCT account_id)>=(SELECT min_accounts FROM params))
SELECT DISTINCT r.transaction_id, 'ANOMALOUS_CLUSTER', fi.risk_score, CURRENT_TIMESTAMP()
FROM flagged_ids fi
JOIN recent r ON r.id_type=fi.id_type AND r.id_value=fi.id_value;

-- ---------------------------------------------------------------------
-- Rule 05 — High-risk velocity: already at transaction grain.
-- ---------------------------------------------------------------------
INSERT INTO FRAUD.DETECTION_RESULTS
WITH params AS (SELECT 5 AS min_window_txns, 2000.00 AS spend_floor),
approved AS (
    SELECT t.*, a.kyc_status, a.is_high_risk_segment
    FROM FRAUD.TRANSACTIONS t JOIN FRAUD.ACCOUNTS a ON a.account_id=t.account_id
    WHERE t.auth_result='APPROVED'),
rolling AS (
    SELECT account_id, transaction_id, kyc_status, is_high_risk_segment,
        SUM(transaction_amount) OVER (PARTITION BY account_id ORDER BY created_at
            RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW) AS roll_spend,
        COUNT(*) OVER (PARTITION BY account_id ORDER BY created_at
            RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW) AS roll_txns
    FROM approved)
SELECT transaction_id, 'HIGH_RISK_VELOCITY',
    0.4*LEAST(roll_spend/10000.0,1)
    +0.3*IFF(is_high_risk_segment,1,0)+0.3*IFF(kyc_status<>'VERIFIED',1,0),
    CURRENT_TIMESTAMP()
FROM rolling CROSS JOIN params p
WHERE roll_txns>=p.min_window_txns AND roll_spend>=p.spend_floor;
