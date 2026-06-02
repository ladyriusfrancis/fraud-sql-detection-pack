# Investigation Playbook

How an analyst turns a rule hit into a disposition. Each section maps a
detection to the pivots that confirm or clear it.

## 01 — Card testing velocity

**Signal:** one device/IP, many cards, many declines, tiny amounts, short
window.

1. Pull the flagged window's `transaction_ids` and confirm the distinct-card
   count and decline reasons (`CVV_FAIL`, `DO_NOT_HONOR` dominate testing).
2. Check whether any attempts in the window were **approved** — those are
   the live cards the tester found; escalate them for immediate block.
3. Pivot on `device_id` and `ip_address` across a wider window for the same
   pattern at other merchants.

**Action:** block the device/IP, force step-up auth, and flag any approved
cards from the window to issuers.

## 02 — ATO login/payment mismatch

**Signal:** successful login from a new country/device after failures, then
a fast high-value payment.

1. Confirm the login country/device are genuinely new for the account
   (`docs/data_dictionary.md` → `LOGIN_EVENTS`).
2. Inspect the preceding failures — a tight burst from one IP is credential
   stuffing; spread-out failures may be a forgetful legitimate user.
3. Compare the payment amount and merchant to the account's history.

**Action:** if confirmed, freeze the session, reverse the payment if still
recoverable, force a password reset, and re-verify the device.

## 03 — Merchant abuse

**Signal:** merchant-day decline rate far above peers (high robust z-score).

1. Profile the merchant over time — is this a one-day spike or a sustained
   pattern? Sustained high declines suggest a conduit; a spike may be an
   outage or a campaign.
2. Look at distinct cards/accounts per day — a real merchant abused as a
   tester target differs from a merchant *account* set up for laundering.
3. Cross-reference with card-testing hits (rule 01) at the same merchant.

**Action:** for confirmed abuse, suspend the merchant, hold settlement, and
review historical volume for clawback.

## 04 — Anomalous cluster

**Signal:** one device/IP linked to many unrelated accounts.

1. Pull the `linked_accounts` set and check for shared attributes beyond the
   identifier (emails, funding instruments, signup timestamps).
2. Distinguish infrastructure sharing that is benign (corporate NAT, public
   Wi-Fi, family devices) from a ring (new accounts, promo abuse, rapid
   cash-out).
3. Expand one hop: do the linked accounts share *other* identifiers with
   each other?

**Action:** for a confirmed ring, action the cluster together, not account
by account — partial action just lets the ring rebalance.

## 05 — High-risk payment velocity

**Signal:** rolling 24h approved count and spend cross thresholds.

1. Compare the burst to the account's lifetime spend pattern — a genuine
   large purchase is usually one transaction, not a rapid series.
2. Check KYC status and high-risk-segment flags feeding the score.
3. Look at merchants and shipping/fulfillment if available — bust-outs
   concentrate on resellable goods.

**Action:** velocity-limit the account, hold pending review, and re-verify
before releasing further authorizations.

## General notes

- Always record the disposition back into `FRAUD_LABELS` — the monitoring
  harness is only as good as the labels it reads.
- A single transaction can be flagged by multiple rules; corroborating
  signals across rules raise confidence and should bump review priority.
