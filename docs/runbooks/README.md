# Runbooks

One runbook per alert name. Every alert rule links here through its
`runbook_url` annotation.

| Alert                              | Severity | Runbook |
|------------------------------------|----------|---------|
| AvailabilityBudgetBurnPage         | critical | [availability-budget-burn-page.md](availability-budget-burn-page.md) |
| AvailabilityBudgetBurnTicket       | warning  | [availability-budget-burn-ticket.md](availability-budget-burn-ticket.md) |
| LatencyBudgetBurnPage              | critical | [latency-budget-burn-page.md](latency-budget-burn-page.md) |
| LatencyBudgetBurnTicket            | warning  | [latency-budget-burn-ticket.md](latency-budget-burn-ticket.md) |
| SLOMetricsAbsent                   | critical | [slo-metrics-absent.md](slo-metrics-absent.md) |
| PrometheusTargetDown               | warning  | [prometheus-target-down.md](prometheus-target-down.md) |
| PrometheusRuleEvaluationFailures   | critical | [prometheus-rule-evaluation-failures.md](prometheus-rule-evaluation-failures.md) |
| AlertmanagerNotificationsFailing   | warning  | [alertmanager-notifications-failing.md](alertmanager-notifications-failing.md) |
| Watchdog                           | none     | [watchdog.md](watchdog.md) |
| ScrapeSuccessBudgetBurnTicket      | warning  | [scrape-success-budget-burn-ticket.md](scrape-success-budget-burn-ticket.md) |

## Conventions

- PromQL snippets are meant for the Prometheus UI at http://localhost:9090
  after `make ports` (or `bash scripts/port-forward.sh`).
- `kubectl` commands assume the `kind-slo-lab` context.
- "Escalation" names roles, not people. In this lab you are every role.
