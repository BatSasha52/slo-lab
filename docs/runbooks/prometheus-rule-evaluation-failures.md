# PrometheusRuleEvaluationFailures

## Meaning

During the last 5 minutes, Prometheus failed to evaluate one or more rules
in the group named in `rule_group`. Recording rules in that group stop
producing data and its alerts stop updating, so SLO alerts may be silently
broken.

## Impact

No direct user impact. Alerting coverage may be lost.

## Checks

1. Which rule fails, and with what error. In the Prometheus UI: Status >
   Rule health, look for rules with an error. Or:
   ```bash
   kubectl logs -n monitoring prometheus-kps-prometheus-0 -c prometheus --tail=200 | grep -i rule
   ```
2. Common causes: a query that returns series with duplicate label sets after
   a label change ("many-to-many matching not allowed"), or a query on a long
   window timing out.
3. Validate the rules locally:
   ```bash
   promtool check rules rules/*.yaml
   promtool test rules rules/tests/*.test.yaml
   ```

## Mitigation

Revert the last change to `rules/` and re-apply with `make rules`. If the
cause is a new label on the scraped metrics, fix the aggregation (`sum by`)
so the result has unique label sets again.

## Escalation

Monitoring platform owner. Treat as urgent if an SLO rule group is affected.
