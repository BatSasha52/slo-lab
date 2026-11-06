# LatencyBudgetBurnPage

## Meaning

The share of `/work` requests taking 300 ms or longer is high enough to spend
the 28-day latency error budget at least 14.4x too fast (1h/5m windows: over
72% of requests slow) or 6x too fast (6h/30m windows: over 30% slow).

Because the budget is 5%, the maximum possible burn rate is 20x. With full
windows, the 1h/5m condition only fires after about 43 minutes of nearly
every request being slow. By the time this pages, users have been affected
for a while.

## Impact

Most requests are slow. Clients with timeouts under a few hundred
milliseconds may be failing outright. That can show up as an availability
problem on their side but not in this service's 5xx count.

## Checks

1. Latency right now:
   ```promql
   histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="demo-app",route="/work"}[1m])))
   slo:sli_error:ratio_rate5m{slo="latency"}
   ```
2. One pod or all of them:
   ```promql
   histogram_quantile(0.95, sum by (le, pod) (rate(http_request_duration_seconds_bucket{job="demo-app",route="/work"}[5m])))
   ```
3. Resource pressure. CPU throttling makes every request slower:
   ```promql
   sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="slo-lab",container="demo-app"}[5m]))
   ```
   ```bash
   kubectl describe pods -n slo-lab -l app.kubernetes.io/name=demo-app | grep -A3 -i "last state"
   ```
4. Load. A traffic spike can exceed capacity:
   ```promql
   sum(rate(http_requests_total{job="demo-app",route="/work"}[1m]))
   ```
5. Injected latency: `bash scripts/fault.sh show`.

## Mitigation

- Injected fault: `bash scripts/fault.sh clear`.
- Capacity: `kubectl scale deployment/demo-app -n slo-lab --replicas=4`.
- Bad rollout: `kubectl rollout undo deployment/demo-app -n slo-lab`.

## Escalation

If latency does not recover within 15 minutes of mitigation, escalate to the
service owner.
