# Watchdog

## Meaning

This alert fires all the time, on purpose. It proves the whole chain works:
Prometheus evaluates rules and sends alerts to Alertmanager, and
Alertmanager delivers notifications. It is routed to the `watchdog` receiver
every 5 minutes.

The useful signal is its absence. In production the receiver would be an
external dead-man's-switch service that pages when the heartbeat stops
arriving. That service has to run outside the monitored system, or it fails
along with it. In this lab the receiver only logs.

## Impact

None while it fires. If it stops, no other alert can be trusted.

## Checks (when the heartbeat stops)

1. Is the alert still firing in Prometheus?
   ```promql
   ALERTS{alertname="Watchdog"}
   ```
   If not, Prometheus is not evaluating rules. Check the Prometheus pod and
   `PrometheusRuleEvaluationFailures`.
2. Does Alertmanager have it?
   ```bash
   kubectl get --raw '/api/v1/namespaces/monitoring/services/http:kps-alertmanager:9093/proxy/api/v2/alerts?filter=alertname%3D%22Watchdog%22'
   ```
   If Prometheus has it but Alertmanager does not, check that Prometheus can
   reach Alertmanager (Prometheus logs, and Status > Runtime & build
   information in the UI).
3. Did the receiver log it?
   ```bash
   kubectl logs -n monitoring deployment/alert-receiver --tail=50 | grep watchdog
   ```

## Mitigation

Restore whichever link in the chain is broken. Until it is fixed, check the
Prometheus alerts page by hand.

## Escalation

Monitoring platform owner, immediately. This alert is how "monitoring is
down" gets noticed.
