-- =====================================================================
-- Load sample data into the FRAUD tables (Snowflake)
-- =====================================================================
-- Loads the CSVs in ../data into the tables created by snowflake_schema.sql
-- using a named file format and a user stage. Run snowflake_schema.sql
-- first. Adjust the PUT source path to wherever you cloned the repo.
-- =====================================================================

USE SCHEMA FRAUD;

CREATE OR REPLACE FILE FORMAT FRAUD.CSV_FF
    TYPE = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE STAGE FRAUD.SAMPLE_STAGE FILE_FORMAT = FRAUD.CSV_FF;

-- Upload local files to the stage (run from SnowSQL; path is client-side).
PUT 'file://data/sample_accounts.csv'      @FRAUD.SAMPLE_STAGE OVERWRITE = TRUE AUTO_COMPRESS = TRUE;
PUT 'file://data/sample_transactions.csv'  @FRAUD.SAMPLE_STAGE OVERWRITE = TRUE AUTO_COMPRESS = TRUE;
PUT 'file://data/sample_login_events.csv'  @FRAUD.SAMPLE_STAGE OVERWRITE = TRUE AUTO_COMPRESS = TRUE;
PUT 'file://data/sample_labels.csv'        @FRAUD.SAMPLE_STAGE OVERWRITE = TRUE AUTO_COMPRESS = TRUE;

COPY INTO FRAUD.ACCOUNTS
    FROM @FRAUD.SAMPLE_STAGE/sample_accounts.csv.gz
    FILE_FORMAT = (FORMAT_NAME = FRAUD.CSV_FF) ON_ERROR = ABORT_STATEMENT;

COPY INTO FRAUD.TRANSACTIONS
    FROM @FRAUD.SAMPLE_STAGE/sample_transactions.csv.gz
    FILE_FORMAT = (FORMAT_NAME = FRAUD.CSV_FF) ON_ERROR = ABORT_STATEMENT;

COPY INTO FRAUD.LOGIN_EVENTS
    FROM @FRAUD.SAMPLE_STAGE/sample_login_events.csv.gz
    FILE_FORMAT = (FORMAT_NAME = FRAUD.CSV_FF) ON_ERROR = ABORT_STATEMENT;

COPY INTO FRAUD.FRAUD_LABELS
    FROM @FRAUD.SAMPLE_STAGE/sample_labels.csv.gz
    FILE_FORMAT = (FORMAT_NAME = FRAUD.CSV_FF) ON_ERROR = ABORT_STATEMENT;
