# AvailabilityBudgetBurnTicket

## Meaning

The availability error budget is being spent at least 3x too fast over a day
(1d/2h windows) or faster than it is replenished over three days (1x, 3d/6h
windows). Nothing is urgent, but at this rate the SLO will be missed before
the 28-day window ends.

While an `AvailabilityBudgetBurnPage` is firing, Alertmanager suppresses this
ticket (inhibition rule in `monitoring/alertmanager.yaml`). The ticket often
arrives right after a page resolves, because the longer windows still contain
the incident.

## Impact

No immediate user harm beyond a low error rate. The budget for planned risk
(deploys, experiments) is shrinking.

## Checks

1. How much budget is left, and how fast it is going:
   ```promql
   slo:error_budget_remaining:ratio{slo="availability"}
   slo:sli_error:ratio_rate1d{slo="availability"} / 0.005
   ```
2. Whether this is a recent incident's tail or a steady leak. A steady leak
   shows a flat non-zero error rate over days:
   ```promql
   sum by (code) (rate(http_requests_total{job="demo-app",route="/work",code=~"5.."}[1h]))
   ```
3. Whether a page fired recently (Alertmanager UI, or the "Firing SLO and
   meta alerts" dashboard panel).

## Mitigation

- If it is the tail of an incident that is already resolved: confirm the 5m
  ratio is back to normal and let the ticket resolve on its own as the
  windows move past the incident.
- If it is a steady leak: find the failing requests in the logs and schedule
  a fix during working hours.
- If the remaining budget is low, consider pausing risky changes until it
  recovers.

## Escalation

Assign to the owning team's backlog during working hours. No out-of-hours
escalation.
