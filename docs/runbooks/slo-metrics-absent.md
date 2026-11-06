# SLOMetricsAbsent

## Meaning

For 5 minutes Prometheus has had no `demo-app` target with `up == 1`. Either
every pod is down, or scraping is broken (ServiceMonitor, Service selector,
Prometheus itself).

The SLO burn-rate alerts are computed from these metrics. While this alert
fires they cannot fire, so treat it as a possible outage until proven
otherwise.

## Impact

Unknown until checked: anything from a monitoring blind spot to a complete
outage.

## Checks

1. Are the pods there and ready?
   ```bash
   kubectl get pods -n slo-lab -l app.kubernetes.io/name=demo-app -o wide
   kubectl get endpointslices -n slo-lab -l kubernetes.io/service-name=demo-app
   ```
2. Can the service answer at all, bypassing Prometheus?
   ```bash
   kubectl get --raw /api/v1/namespaces/slo-lab/services/http:demo-app:8080/proxy/readyz
   ```
3. What does Prometheus see? In the UI: Status > Target health, filter on
   `demo-app`. Or:
   ```promql
   up{job="demo-app"}
   ```
   No series at all means service discovery found nothing. Compare the
   ServiceMonitor selector with the Service labels:
   ```bash
   kubectl get servicemonitor demo-app -n slo-lab -o yaml
   kubectl get service demo-app -n slo-lab --show-labels
   ```

## Mitigation

- Pods down or crash-looping: check `kubectl describe pod` and
  `kubectl logs --previous`, then roll back the last change with
  `kubectl rollout undo deployment/demo-app -n slo-lab`.
- Selector or ServiceMonitor broken: re-apply the manifests with
  `kubectl apply -k k8s`.

## Escalation

If pods are down and a rollback does not help within 15 minutes, escalate to
the service owner. If only scraping is broken, escalate to the monitoring
platform owner.
