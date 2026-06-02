# Precision / Recall Framework

Fraud detection is a class-imbalanced binary classification problem.
Confirmed fraud is rare, so accuracy is meaningless (flagging nothing scores
99%+). This pack measures every rule with precision, recall, and the
trade-off between them.

## Definitions

For a given rule, every transaction is either flagged (positive prediction)
or not, and is either confirmed fraud (actual positive) or not:

| | Actual fraud | Actual legit |
|--|-------------|--------------|
| **Flagged** | TP | FP |
| **Not flagged** | FN | TN |

- **Precision** = `TP / (TP + FP)` — of what we flagged, how much was real
  fraud. Low precision means analysts waste time on false alarms and good
  customers get blocked.
- **Recall** = `TP / (TP + FN)` — of all real fraud, how much we caught.
  Low recall means fraud slips through and chargebacks land.
- **False-positive rate** = `FP / (FP + TN)` — the share of legitimate
  transactions wrongly flagged. The customer-experience cost.
- **F1** = `2·TP / (2·TP + FP + FN)` — harmonic mean of precision and
  recall; a single number for balanced comparison.

## The trade-off

Tightening a rule's threshold raises precision and lowers recall; loosening
it does the reverse. There is no universally correct point — it depends on
the cost of a missed fraud (chargeback + fees + liability) versus the cost
of a false positive (lost good transaction + review labor + customer
friction). `evaluation/threshold_testing.sql` sweeps the score cutoff and
reports precision/recall at each step so you can plot the curve and choose
the knee, or the point that hits a target precision floor.

## Choosing an operating point

A practical procedure:

1. Decide the **non-negotiable constraint** — usually a maximum tolerable
   false-positive rate (e.g. "block no more than 0.5% of good traffic") or a
   minimum precision for an auto-action queue (e.g. "auto-decline only at
   precision >= 0.95").
2. Run `threshold_testing.sql` and pick the lowest threshold that still
   satisfies the constraint — this maximizes recall within your budget.
3. Route by score band, not a single cutoff: high score → auto-action,
   medium → manual review queue, low → monitor only. This recovers recall
   without sacrificing precision on the auto-action path.

## Monitoring for decay

Fraud is adversarial; a tuned rule degrades as attackers adapt. Schedule
`queries/06_precision_recall_monitoring.sql` (e.g. daily) and alert when a
rule's precision or recall drops more than a set amount versus its trailing
baseline. A sudden precision drop usually means a new legitimate pattern is
tripping the rule; a recall drop usually means attackers have shifted below
your thresholds.

## Label caveats

Metrics are only as good as the labels. Chargeback labels arrive with a lag
(disputes can take weeks), so recent periods look artificially clean — the
fraud is there, just not yet labeled. Account for label maturity when
comparing periods, and prefer evaluating on windows old enough for
chargebacks to have settled.
