-- =====================================================================
-- 02 — Account Takeover (ATO): login / payment mismatch
-- =====================================================================
-- Typology: An attacker authenticates from a new device/country (often
-- after a burst of failed logins), then quickly pushes a high-value
-- payment. Signature = successful login from a country/device the
-- account has never used, preceded by failures, followed within minutes
-- by an abnormally large approved charge.
--
-- Detection logic:
--   1. Establish each account's historical "known" countries/devices.
--   2. Find successful logins from a NEW country or device that were
--      preceded by >= N failures in a short window.
--   3. Join to APPROVED transactions occurring within M minutes whose
--      amount exceeds the account's typical spend.
--
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres.
-- =====================================================================

WITH params AS (
    SELECT
        60      AS payment_window_minutes,  -- login -> payment proximity
        30      AS failure_lookback_minutes,
        3       AS min_recent_failures,
        3.0     AS amount_multiplier         -- x account's historical avg
),
account_history AS (
    -- Known countries/devices observed BEFORE the evaluation horizon.
    SELECT account_id, ARRAY_AGG(DISTINCT country)   AS known_countries,
                       ARRAY_AGG(DISTINCT device_id) AS known_devices
    FROM FRAUD.LOGIN_EVENTS
    WHERE login_result = 'SUCCESS'
    GROUP BY account_id
),
account_spend AS (
    SELECT account_id, AVG(transaction_amount) AS avg_amount
    FROM FRAUD.TRANSACTIONS
    WHERE auth_result = 'APPROVED'
    GROUP BY account_id
),
recent_failures AS (
    -- Count failed logins in the lookback window preceding each success.
    SELECT
        s.login_id,
        COUNT(f.login_id) AS preceding_failures
    FROM FRAUD.LOGIN_EVENTS s
    LEFT JOIN FRAUD.LOGIN_EVENTS f
        ON f.account_id = s.account_id
       AND f.login_result = 'FAILURE'
       AND f.created_at <  s.created_at
       AND f.created_at >= DATEADD('minute',
              -(SELECT failure_lookback_minutes FROM params), s.created_at)
    WHERE s.login_result = 'SUCCESS'
    GROUP BY s.login_id
),
suspicious_logins AS (
    SELECT
        s.login_id, s.account_id, s.country AS login_country,
        s.device_id AS login_device, s.created_at AS login_at,
        rf.preceding_failures,
        h.known_countries, h.known_devices
    FROM FRAUD.LOGIN_EVENTS s
    JOIN account_history h ON h.account_id = s.account_id
    JOIN recent_failures rf ON rf.login_id = s.login_id
    CROSS JOIN params p
    WHERE s.login_result = 'SUCCESS'
      AND rf.preceding_failures >= p.min_recent_failures
      AND (NOT ARRAY_CONTAINS(s.country::VARIANT,   h.known_countries)
        OR NOT ARRAY_CONTAINS(s.device_id::VARIANT, h.known_devices))
)
SELECT
    sl.account_id,
    sl.login_id,
    sl.login_at,
    sl.login_country,
    sl.login_device,
    sl.preceding_failures,
    t.transaction_id,
    t.transaction_amount,
    sp.avg_amount                                   AS account_avg_amount,
    DATEDIFF('minute', sl.login_at, t.created_at)   AS minutes_login_to_payment,
    ROUND(
        0.4
      + 0.3 * LEAST(sl.preceding_failures / 5.0, 1)
      + 0.3 * LEAST(t.transaction_amount / NULLIF(sp.avg_amount,0) / 5.0, 1),
    3)                                              AS risk_score,
    'ATO' AS detection_rule
FROM suspicious_logins sl
CROSS JOIN params p
JOIN FRAUD.TRANSACTIONS t
    ON t.account_id = sl.account_id
   AND t.auth_result = 'APPROVED'
   AND t.created_at >= sl.login_at
   AND t.created_at <  DATEADD('minute', p.payment_window_minutes, sl.login_at)
LEFT JOIN account_spend sp ON sp.account_id = sl.account_id
WHERE t.transaction_amount >= p.amount_multiplier * COALESCE(sp.avg_amount, 0)
ORDER BY risk_score DESC;
