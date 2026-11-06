# AlertmanagerNotificationsFailing

## Meaning

For 5 minutes, Alertmanager has failed to deliver notifications through the
`integration` named in the alert (here, `webhook`). Pages and tickets may not
be reaching anyone.

This alert goes out through the same Alertmanager, so it only arrives if some
route still works. If nothing works, the Watchdog heartbeat stopping is what
should catch it.

## Impact

Alerts are firing in Prometheus, but nobody is being told.

## Checks

1. Failure rate by integration, and the error message:
   ```promql
   sum by (integration) (rate(alertmanager_notifications_failed_total[5m]))
   ```
   ```bash
   kubectl logs -n monitoring alertmanager-kps-alertmanager-0 -c alertmanager --tail=100 | grep -i notify
   ```
2. Is the receiver up?
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=alert-receiver
   kubectl get endpointslices -n monitoring -l kubernetes.io/service-name=alert-receiver
   ```
3. Is the configuration valid?
   ```bash
   amtool check-config monitoring/alertmanager.yaml
   ```

## Mitigation

- Receiver down: `kubectl rollout restart deployment/alert-receiver -n monitoring`.
- Wrong config: fix `monitoring/alertmanager.yaml` and re-run
  `bash scripts/deploy-monitoring.sh`.
- While delivery is broken, watch the Alertmanager UI
  (http://localhost:9093) by hand for anything critical.

## Escalation

Monitoring platform owner, urgently. When notifications are not delivered,
no other alert can be relied on.
