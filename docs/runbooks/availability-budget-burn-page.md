# AvailabilityBudgetBurnPage

## Meaning

The share of `/work` requests returning 5xx is high enough to spend the
28-day availability error budget at least 14.4x too fast (1h/5m windows) or
6x too fast (6h/30m windows). The `long_window` label says which.

## Impact

Users are getting errors now. At 14.4x the whole budget is gone in under two
days.

## Checks

1. Confirm the error ratio and see whether it is still rising:
   ```promql
   slo:sli_error:ratio_rate5m{slo="availability"}
   sum by (code) (rate(http_requests_total{job="demo-app",route="/work"}[1m]))
   ```
2. Check whether the errors come from one pod or all of them:
   ```promql
   sum by (pod) (rate(http_requests_total{job="demo-app",route="/work",code=~"5.."}[5m]))
   ```
3. Look at the pods and recent changes:
   ```bash
   kubectl get pods -n slo-lab -l app.kubernetes.io/name=demo-app -o wide
   kubectl rollout history deployment/demo-app -n slo-lab
   kubectl get events -n slo-lab --sort-by=.lastTimestamp | tail -20
   ```
4. Check whether a fault is injected (this lab's most likely cause):
   ```bash
   bash scripts/fault.sh show
   ```
   or `demo_app_fault_error_rate` on the "Injected faults" dashboard panel.
5. Read the application logs:
   ```bash
   kubectl logs -n slo-lab -l app.kubernetes.io/name=demo-app --tail=100 --prefix
   ```

## Mitigation

- Injected fault: `bash scripts/fault.sh clear`.
- Bad rollout: `kubectl rollout undo deployment/demo-app -n slo-lab`.
- Single bad pod: `kubectl delete pod <name> -n slo-lab`. The Deployment
  replaces it, and the PodDisruptionBudget does not block a direct delete.
- Mitigate first, investigate after. The page resolves a few minutes after
  the 5m (or 30m) ratio drops below the threshold.
- A page can still arrive a minute or two after a mitigation: the alert may
  have been pending, and its short window still holds the errors. Before
  escalating, check whether `slo:sli_error:ratio_rate5m{slo="availability"}`
  is already falling. If it is, the fix is working.

## Escalation

If errors continue for 15 minutes after a rollback or pod replacement,
escalate to the service owner. Afterwards, if more than 5% of the budget was
spent, open a postmortem using `docs/postmortems/TEMPLATE.md`.
