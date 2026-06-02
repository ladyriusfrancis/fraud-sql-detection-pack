# Data Dictionary

All tables live in the `FRAUD` schema. Adjust the database/schema prefix to
your environment. See `schema/snowflake_schema.sql` for DDL.

## FRAUD.ACCOUNTS — one row per customer account

| Column | Type | Description |
|--------|------|-------------|
| `account_id` | STRING (PK) | Surrogate account key. |
| `email` | STRING | Account email address. |
| `country` | STRING | ISO-3166 alpha-2 home country. |
| `account_created_at` | TIMESTAMP_NTZ | Signup timestamp. |
| `kyc_status` | STRING | `VERIFIED` / `PENDING` / `FAILED`. |
| `is_high_risk_segment` | BOOLEAN | Analyst-flagged risky cohort. |

## FRAUD.TRANSACTIONS — one row per authorization / payment attempt

| Column | Type | Description |
|--------|------|-------------|
| `transaction_id` | STRING (PK) | Surrogate transaction key. |
| `account_id` | STRING (FK) | References `ACCOUNTS.account_id`. |
| `card_fingerprint` | STRING | Hashed PAN, stable per physical card. |
| `merchant_id` | STRING | Merchant identifier. |
| `merchant_category` | STRING | MCC bucket (e.g. `DIGITAL_GOODS`). |
| `transaction_amount` | NUMBER(18,2) | Transaction amount. |
| `currency` | STRING | ISO-4217 currency code. |
| `auth_result` | STRING | `APPROVED` / `DECLINED`. |
| `decline_reason` | STRING | e.g. `CVV_FAIL`, `INSUFFICIENT_FUNDS`. |
| `ip_address` | STRING | Source IP at authorization. |
| `device_id` | STRING | Device fingerprint. |
| `bin_country` | STRING | Card-issuer (BIN) country. |
| `is_card_present` | BOOLEAN | Card-present vs card-not-present. |
| `created_at` | TIMESTAMP_NTZ | Authorization timestamp. |

## FRAUD.LOGIN_EVENTS — authentication events (used for ATO)

| Column | Type | Description |
|--------|------|-------------|
| `login_id` | STRING (PK) | Surrogate login key. |
| `account_id` | STRING (FK) | References `ACCOUNTS.account_id`. |
| `ip_address` | STRING | Source IP. |
| `device_id` | STRING | Device fingerprint. |
| `country` | STRING | Geo-IP country at login. |
| `login_result` | STRING | `SUCCESS` / `FAILURE`. |
| `created_at` | TIMESTAMP_NTZ | Login timestamp. |

## FRAUD.FRAUD_LABELS — ground truth for evaluation

| Column | Type | Description |
|--------|------|-------------|
| `transaction_id` | STRING (PK, FK) | References `TRANSACTIONS.transaction_id`. |
| `is_confirmed_fraud` | BOOLEAN | `TRUE` = chargeback/confirmed fraud. |
| `fraud_type` | STRING | `CARD_TESTING` / `ATO` / `ABUSE` / `OTHER`. |
| `labeled_at` | TIMESTAMP_NTZ | When the disposition was recorded. |
| `label_source` | STRING | `CHARGEBACK` / `MANUAL_REVIEW` / `RULE`. |

> Transactions absent from `FRAUD_LABELS` are treated as legitimate
> (true negatives) by the evaluation harness.

## FRAUD.DETECTION_RESULTS — rule output (built by the harness)

| Column | Type | Description |
|--------|------|-------------|
| `transaction_id` | STRING | Flagged transaction. |
| `detection_rule` | STRING | Which rule fired (e.g. `CARD_TESTING`). |
| `risk_score` | FLOAT | Rule score in `[0,1]`. |
| `scored_at` | TIMESTAMP_NTZ | When the rule was run. |
