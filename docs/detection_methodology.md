# Detection Methodology

This pack models each fraud rule as a binary classifier over transactions.
A rule reads raw events, applies a typology-specific heuristic, and emits
scored hits. Hits are materialized at transaction grain so they can be
compared directly against confirmed-fraud labels.

## Design principles

1. **One typology per rule.** Each query targets a single fraud pattern.
   Composite scoring is left to the consumer (e.g. union all rule outputs
   and take the max score). This keeps each rule auditable and individually
   measurable.
2. **Thresholds as data.** Every tunable lives in a `params` CTE at the top
   of the query. No magic numbers buried in predicates.
3. **Scored, not just boolean.** Every hit carries a `risk_score` in
   `[0,1]` so downstream queues can prioritize and so threshold sweeps
   (`evaluation/threshold_testing.sql`) are possible.
4. **Robust statistics where populations are noisy.** Rule 03 uses a
   median/MAD modified z-score rather than mean/stddev, because a few
   contaminating bad merchants would otherwise inflate the mean and hide
   true outliers.
5. **Grain discipline.** Some rules naturally produce entity-level hits
   (a flagged device-window, a flagged merchant-day). The evaluation
   harness expands those to the underlying transactions so all rules are
   scored on a common grain.

## The five rules

### 01 — Card testing velocity
Card testers fire many low-value authorizations across many stolen card
numbers from shared infrastructure to find live cards. The query buckets
transactions into fixed time windows per `(device_id, ip_address)` and
flags windows with a high distinct-card count, a high decline rate, and a
low average amount. All three conditions must hold, which is what separates
testing from ordinary high-volume merchants.

### 02 — ATO login/payment mismatch
Account takeover shows up as a successful authentication from a device or
country the account has never used, usually preceded by a burst of failed
logins, followed quickly by an abnormally large payment. The query
establishes each account's **prior** known countries/devices (strictly
before the candidate login — this is important; including the suspicious
login itself would mask the novelty), requires a minimum number of recent
preceding failures, and joins to a high-value approved payment within a
short window.

### 03 — Merchant abuse
A conduit merchant exhibits an authorization profile far outside its peers,
most visibly an elevated decline rate. The query builds daily per-merchant
profiles and scores each with a **robust modified z-score**
`0.6745 * (x - median) / MAD` over merchant-days clearing a minimum volume.
Robustness matters because the merchant population is small and often
contains more than one bad actor.

### 04 — Anomalous cluster
Fraud rings reuse devices and IPs across otherwise unrelated accounts. The
query unpivots `device_id` and `ip_address` into a single identifier grain
and flags identifiers whose distinct-account fan-out exceeds a threshold —
a SQL expression of single-hop graph density. The linked account set is
returned so an analyst can pivot straight into a case.

### 05 — High-risk payment velocity
A bust-out account spends fast and large in a short window. The query uses
a window function to compute rolling 24h approved count and spend, and flags
rows clearing both a count minimum and an **absolute spend floor**. An
absolute floor is used deliberately: a bust-out inflates the account's own
average, so self-relative baselines become unstable exactly when you need
them. The floor is a tunable, currency-specific parameter.

## From hits to metrics

`evaluation/precision_recall_harness.sql` rebuilds
`FRAUD.DETECTION_RESULTS(transaction_id, detection_rule, risk_score,
scored_at)` by running every rule and expanding entity-level hits to
transactions. `queries/06_precision_recall_monitoring.sql` then joins those
predictions against `FRAUD.FRAUD_LABELS` to compute the confusion matrix and
derived metrics per rule. Schedule query 06 (e.g. daily) to watch for rule
decay over time.
