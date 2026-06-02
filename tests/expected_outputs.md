# Expected Outputs

These are the reference results produced by running every detection rule
against the bundled synthetic dataset (`data/`). The logic was validated
end-to-end against the sample data; your numbers should match these when
you load the sample data and run `evaluation/precision_recall_harness.sql`
followed by `queries/06_precision_recall_monitoring.sql`.

## Dataset summary

| Item | Count |
|------|-------|
| Accounts | 40 |
| Transactions | 776 |
| Login events | 24 |
| Confirmed-fraud transactions (labels) | 111 |

## Per-rule metrics (transaction grain)

| Detection rule | TP | FP | FN | Precision | Recall |
|----------------|----|----|----|-----------|--------|
| CARD_TESTING | 45 | 0 | 66 | 1.000 | 0.405 |
| ATO | 3 | 0 | 108 | 1.000 | 0.027 |
| MERCHANT_ABUSE | 80 | 15 | 31 | 0.842 | 0.721 |
| ANOMALOUS_CLUSTER | 12 | 0 | 99 | 1.000 | 0.108 |
| HIGH_RISK_VELOCITY | 8 | 2 | 103 | 0.800 | 0.072 |

Per-rule recall is intentionally low for narrow rules (each rule only
targets its own typology, so fraud of other types counts against its
recall denominator). The meaningful figure is the **combined** system.

## Combined system (a transaction is flagged if ANY rule fires)

| Metric | Value |
|--------|-------|
| True positives | 103 |
| False positives | 17 |
| False negatives | 8 |
| True negatives | 648 |
| **Precision** | **0.858** |
| **Recall** | **0.928** |
| False-positive rate | 0.026 |
| F1 score | 0.892 |

## Notes

- These figures depend on the default thresholds defined in each query's
  `params` CTE. Changing a threshold changes the metrics — use
  `evaluation/threshold_testing.sql` to see the trade-off curve.
- The synthetic generator is seeded (`random.seed(42)`); regenerating the
  data reproduces the same rows and therefore the same metrics.
- `MERCHANT_ABUSE` false positives are non-labeled *approved* transactions
  at a flagged merchant — expected, because the rule flags at merchant-day
  grain. Precision is reported at transaction grain.
