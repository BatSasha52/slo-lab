# ScrapeSuccessBudgetBurnTicket

## Meaning

More than 0.3% of all scrape attempts failed over the last day (1d/2h
windows), or more than 0.1% over three days (3d/6h windows). The platform's
scrape-success SLO (99.9% over 28 days) will be missed if this continues.
This is the monitoring platform's own SLO, not demo-app's.

## Impact

Some teams' metrics have gaps. Their dashboards show holes, and their
alerts may fire late or not at all for the affected targets.

## Checks

1. Which targets fail most:
   ```promql
   sort_desc(sum by (job) (count_over_time(up[1d]) - sum_over_time(up[1d])))
   ```
2. Whether the failures are one target that is down (the target owner's
   problem) or spread across many (the platform's problem). Spread-out
   failures point at Prometheus itself:
   ```promql
   rate(prometheus_target_scrapes_exceeded_sample_limit_total[1h])
   rate(prometheus_target_scrape_pool_exceeded_target_limit_total[1h])
   prometheus_target_interval_length_seconds{quantile="0.99"}
   ```
   ```bash
   kubectl top pod -n monitoring prometheus-kps-prometheus-0
   ```

## Mitigation

- A single broken target: tell its owner and, if it is permanently gone,
  remove its ServiceMonitor.
- Prometheus overloaded: raise its resources in
  `monitoring/kube-prometheus-stack-values.yaml`, or reduce scrape load.

## Escalation

Monitoring platform team backlog. No out-of-hours escalation.

## Known weakness

`up == 0` also counts failures that are the target's own fault, such as a
crashing app. A production platform would separate failures it owns (timeouts
inside Prometheus, sample limits) from ones the target owns, so that one
broken service does not spend the platform's budget.
