-- =====================================================================
-- Fraud SQL Detection Pack — Snowflake schema
-- =====================================================================
-- Defines the core tables the detection queries run against.
-- Dialect: Snowflake. See dialect_notes/ for BigQuery / Postgres notes.
-- All tables live in the FRAUD schema; adjust the database/schema prefix
-- to match your environment.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS FRAUD;

-- ---------------------------------------------------------------------
-- ACCOUNTS — one row per customer account
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FRAUD.ACCOUNTS (
    account_id          STRING        NOT NULL,        -- surrogate account key
    email               STRING,                        -- account email
    country             STRING,                        -- ISO-3166 alpha-2 home country
    account_created_at  TIMESTAMP_NTZ,                 -- signup timestamp
    kyc_status          STRING,                        -- VERIFIED / PENDING / FAILED
    is_high_risk_segment BOOLEAN      DEFAULT FALSE,   -- analyst-flagged risky cohort
    CONSTRAINT pk_accounts PRIMARY KEY (account_id)
);

-- ---------------------------------------------------------------------
-- TRANSACTIONS — one row per card authorization / payment attempt
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FRAUD.TRANSACTIONS (
    transaction_id      STRING        NOT NULL,        -- surrogate txn key
    account_id          STRING        NOT NULL,        -- FK -> ACCOUNTS
    card_fingerprint    STRING,                        -- hashed PAN, stable per card
    merchant_id         STRING,                        -- merchant identifier
    merchant_category   STRING,                        -- MCC bucket
    transaction_amount  NUMBER(18,2),                  -- amount in minor->major units
    currency            STRING,                        -- ISO-4217
    auth_result         STRING,                        -- APPROVED / DECLINED
    decline_reason      STRING,                        -- e.g. INSUFFICIENT_FUNDS, CVV_FAIL
    ip_address          STRING,                        -- source IP
    device_id           STRING,                        -- device fingerprint
    bin_country         STRING,                        -- card-issuer country
    is_card_present     BOOLEAN,                        -- CP vs CNP
    created_at          TIMESTAMP_NTZ NOT NULL,        -- authorization timestamp
    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id)
);

-- ---------------------------------------------------------------------
-- LOGIN_EVENTS — authentication events, used for ATO detection
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FRAUD.LOGIN_EVENTS (
    login_id            STRING        NOT NULL,
    account_id          STRING        NOT NULL,        -- FK -> ACCOUNTS
    ip_address          STRING,
    device_id           STRING,
    country             STRING,                        -- geo-IP country at login
    login_result        STRING,                        -- SUCCESS / FAILURE
    created_at          TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_login_events PRIMARY KEY (login_id)
);

-- ---------------------------------------------------------------------
-- FRAUD_LABELS — ground truth for precision/recall evaluation
-- ---------------------------------------------------------------------
-- One row per transaction that has a confirmed disposition. Transactions
-- absent from this table are treated as "not confirmed fraud" (negatives)
-- by the evaluation harness unless you choose to restrict to labeled-only.
CREATE OR REPLACE TABLE FRAUD.FRAUD_LABELS (
    transaction_id      STRING        NOT NULL,        -- FK -> TRANSACTIONS
    is_confirmed_fraud  BOOLEAN       NOT NULL,        -- TRUE = chargeback/confirmed
    fraud_type          STRING,                        -- CARD_TESTING / ATO / ABUSE / OTHER
    labeled_at          TIMESTAMP_NTZ,
    label_source        STRING,                        -- CHARGEBACK / MANUAL_REVIEW / RULE
    CONSTRAINT pk_fraud_labels PRIMARY KEY (transaction_id)
);
