# Fraud SQL Detection Pack Case Study

## Objective

Build a reusable fraud detection framework capable of identifying common payment fraud typologies while measuring detection effectiveness through precision and recall.

## Fraud Typologies Covered

- Card Testing
- Account Takeover (ATO)
- Merchant Abuse
- Fraud Rings / Cluster Detection
- High-Risk Payment Velocity

## Architecture

Synthetic Data → Detection Rules → Detection Results → Precision/Recall Monitoring → Threshold Tuning

## Methodology

- Snowflake data warehouse
- Synthetic labeled transaction dataset
- Rule-based detection framework
- Performance evaluation against confirmed fraud labels

## Results

### Card Testing

Precision: 100%
Recall: 40.5%

### ATO Detection

Successfully identified suspicious login-to-payment sequences involving:
- New devices
- Foreign login locations
- Multiple failed login attempts

### Merchant Abuse

Detected merchants exhibiting decline rates significantly above peer baselines.

### Cluster Detection

Identified shared devices and IPs associated with multiple linked accounts.

### High-Risk Payment Velocity

Flagged accounts exhibiting rapid spend accumulation and transaction bursts.

## Future Enhancements

- Automated threshold optimization
- Feature store architecture
- Supervised ML scoring
- Real-time detection pipelines
- Streamlit analytics dashboard
