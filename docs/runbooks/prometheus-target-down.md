# PrometheusTargetDown

## Meaning

Prometheus has failed to scrape one target (see the `job` and `instance`
labels) for 5 minutes. Any alert built on that target's metrics cannot fire.

## Impact

Depends on the target. If one `demo-app` pod cannot be scraped, the SLI is
computed from the other pod only. For cluster components, it hides their own
alerts.

## Checks

1. Which targets, and the last scrape error. In the Prometheus UI: Status >
   Target health. Or:
   ```promql
   up == 0
   ```
2. Is the pod behind the target running?
   ```bash
   kubectl get pods -A -o wide | grep <instance IP>
   ```
3. Can the metrics endpoint be reached from inside the cluster?
   ```bash
   kubectl run curl-check --rm -it --restart=Never --image=curlimages/curl -- \
     curl -sS -m 5 http://<instance>/metrics
   ```

## Mitigation

- Pod not running: fix the workload (see its own alerts or logs).
- Endpoint reachable but the scrape fails: compare the ServiceMonitor port
  and path with what the container exposes.
- Control-plane targets (etcd, scheduler, controller-manager, kube-proxy) on
  a new kind cluster: check that the cluster was created from
  `kind/cluster.yaml`, which binds their metrics endpoints to 0.0.0.0.

## Escalation

Owner of the scraped component, during working hours. If the target is
`demo-app` and `SLOMetricsAbsent` is also firing, follow that runbook
instead.
