# LatencyBudgetBurnTicket

## Meaning

More than 15% of `/work` requests over the last day (1d/2h windows), or more
than 5% over three days (3d/6h windows), took 300 ms or longer. If this
continues, the latency budget will run out before the 28-day window ends.
Suppressed while `LatencyBudgetBurnPage` fires for the same SLO.

## Impact

A noticeable minority of requests is slow. No urgent harm.

## Checks

1. Remaining budget and the trend:
   ```promql
   slo:error_budget_remaining:ratio{slo="latency"}
   slo:sli_error:ratio_rate1d{slo="latency"} / 0.05
   ```
2. Whether the slowness is constant or tied to load. Compare p95 latency with
   the request rate over the last few days on the Service SLO dashboard.
3. Whether resource requests and limits still fit actual usage:
   ```promql
   sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="slo-lab",container="demo-app"}[5m]))
   ```
   ```bash
   kubectl get deployment demo-app -n slo-lab -o jsonpath='{.spec.template.spec.containers[0].resources}'
   ```

## Mitigation

Plan the fix during working hours: profile the slow path, adjust resources,
or add replicas. If it is the tail of a resolved incident, let it resolve.

## Escalation

Owning team's backlog. No out-of-hours escalation.
