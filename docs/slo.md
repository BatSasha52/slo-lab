# SLOs for demo-app

This document defines the service level objectives for the demo service, the
indicators they are measured with, and how the alerting thresholds were
derived. The rules that implement it are in `rules/slo-recording.yaml` and
`rules/slo-alerts.yaml`.

## Scope

- Service: `demo-app` in namespace `slo-lab`.
- User journey: `GET /work`. Health, readiness, metrics and admin endpoints
  are excluded; they are not what users depend on, and probe traffic would
  dilute the ratio.
- Measurement point: the server, via the `http_requests_total` counter and
  the `http_request_duration_seconds` histogram that the app exposes.
- Compliance period: rolling 28 days. Four whole weeks, so every period has
  the same number of weekdays and weekends.

## SLIs and objectives

| SLO          | SLI (good events / valid events)                                     | Objective | Error budget |
|--------------|----------------------------------------------------------------------|-----------|--------------|
| Availability | `/work` responses that are not 5xx / all `/work` responses           | 99.5%     | 0.5%         |
| Latency      | `/work` responses served in under 300 ms / all `/work` responses     | 95%       | 5%           |

Notes on the definitions:

- 4xx responses count as good for availability. They indicate a client
  error, and the service cannot fix them.
- The latency SLI includes failed requests. A fast 500 is good for latency
  and bad for availability, so each failure is counted once, by the SLO it
  belongs to.
- 300 ms must be a histogram bucket boundary (`le="0.3"`). With a boundary at,
  say, 0.25 and 0.5 only, "under 300 ms" could not be counted exactly. The
  bucket list is in `app/slo_app/main.py` with a comment saying so.

The rules store everything as an error ratio (bad / valid) under one metric
name, `slo:sli_error:ratio_rate<window>`, with the SLO in the `slo` label.
The SLI shown on the dashboard is `1 - ratio`.

## Error budget

The error budget is the share of requests allowed to be bad: 0.5% for
availability, 5% for latency. At the load generator's default 10 requests
per second, 28 days is about 24.2 million requests, so the availability
budget is about 121,000 failed requests, or 3.4 hours of complete outage.

`slo:error_budget_remaining:ratio` is
`1 - (error ratio over 28 days / budget)`: 1 means nothing spent, 0 means
exactly used up, negative means the SLO was missed.

## Burn rate

Burn rate is the observed error ratio divided by the budget:

```
burn rate = error ratio over a window / (1 - objective)
```

A burn rate of 1 uses exactly the whole budget over 28 days. A burn rate of
14.4 sustained for one hour uses `14.4 * 1h / 672h = 2.1%` of the 28-day
budget.

Alerting on burn rate instead of on raw error ratio makes the threshold mean
the same thing for every SLO, whatever its target: "we are spending the
budget N times too fast".

## Alerting policy

Four conditions per SLO, following the multiwindow, multi-burn-rate approach
from chapter 5 of Google's *The Site Reliability Workbook*:

| Burn rate | Long window | Short window | Budget spent when it fires | Severity | Alert name                        |
|-----------|-------------|--------------|----------------------------|----------|-----------------------------------|
| 14.4x     | 1h          | 5m           | 2.1%                       | page     | `<SLO>BudgetBurnPage`             |
| 6x        | 6h          | 30m          | 5.4%                       | page     | `<SLO>BudgetBurnPage`             |
| 3x        | 1d          | 2h           | 10.7%                      | ticket   | `<SLO>BudgetBurnTicket`           |
| 1x        | 3d          | 6h           | 10.7%                      | ticket   | `<SLO>BudgetBurnTicket`           |

The burn-rate factors are the workbook's. The workbook derives them for a
30-day period, where they correspond to exactly 2%, 5%, 10% and 10% of the
budget. On 28 days the same factors give the slightly higher figures above.
That difference is not worth non-standard numbers that a reader would have
to re-derive.

The resulting thresholds on the error ratio (threshold = factor x budget):

| Burn rate | Availability (budget 0.5%) | Latency (budget 5%) |
|-----------|----------------------------|---------------------|
| 14.4x     | 7.2% of requests fail      | 72% of requests slow |
| 6x        | 3%                         | 30%                 |
| 3x        | 1.5%                       | 15%                 |
| 1x        | 0.5%                       | 5%                  |

### Why two windows per alert

- The long window decides whether the burn is significant. A single bad
  minute raises a 5-minute ratio sharply but barely moves a 1-hour ratio, so
  it does not page. This case is covered by the test "brief spike does not
  page" in `rules/tests/slo-alerts.test.yaml`.
- The short window (1/12 of the long one) decides whether it is still
  happening. Without it, a 1-hour window keeps the alert firing for up to an
  hour after the problem is fixed. With it, the alert resolves within a few
  minutes of recovery. Covered by "short window resolves the page after
  recovery".

### Why several burn rates

- A fast, severe burn needs a short long-window to be noticed quickly (1h at
  14.4x).
- A slower burn would never cross 14.4x but still exhausts the budget in days
  (6x over 6h).
- Slow leaks that use the budget over weeks are not urgent enough to wake
  someone up and become tickets (3x and 1x).

### `for` durations

Pages use `for: 2m` and tickets `for: 15m`. The short window already filters
noise, so these are kept small: they only absorb a single bad evaluation
around a rule reload or a scrape gap.

### Detection time

For a constant error ratio `e` starting from a clean full window, the long
window crosses its threshold after `window * threshold / e` (if that is
shorter than the window). Add the `for` duration and Alertmanager's
`group_wait` (30s) for the notification.

Availability, fast page (1h window, threshold 7.2%):

| Error ratio | Long window crosses after | Page sent after (approx.) |
|-------------|---------------------------|---------------------------|
| 100%        | 4.3 min                   | 7 min                     |
| 50%         | 8.6 min                   | 11 min                    |
| 10%         | 43 min                    | 46 min                    |
| 7.2% or less| never                     | the 6h page or a ticket catches it |

Latency is different because its budget is ten times larger: even if every
request is slow the burn rate is only 20x. The fast page needs
`60 min * 0.72 = 43 min` of complete slowness before it fires. That is a
direct consequence of choosing a 95% objective. A tighter latency objective
(99% under 300 ms) would page within about 9 minutes for the same incident.
Whether 43 minutes is acceptable is a product decision, not an alerting one.

These figures assume the windows are full of history. On a cluster younger
than the long window, `rate()` only sees the data that exists, so a 6h
window on a 1-hour-old cluster behaves like a 1h window. The 2026-11-05 drill
ran into this: its 6h/30m page fired before the 1h/5m page. See
`docs/postmortems/2026-11-05-fault-injection-drill.md`.

## A second SLO: scrape success for the monitoring platform

`rules/platform-slo.yaml` defines an SLO for the monitoring platform itself.
It shows that the kind of SLI follows from what a service provides:

| Service | What its users rely on | SLI type | SLI |
|---------|------------------------|----------|-----|
| demo-app | answers to requests | availability, latency | non-5xx share, share under 300 ms |
| monitoring platform | their metrics being collected | completeness | share of scrape attempts that succeeded |

- SLI: `sum(sum_over_time(up[w])) / sum(count_over_time(up[w]))` over all
  targets. `up` has one sample per scrape attempt, 1 or 0, so this is
  exactly successful scrapes divided by attempted scrapes.
- Objective: 99.9% over 28 days, so the budget is 0.1% of scrapes.
- Alerts: tickets only (3x over 1d/2h, 1x over 3d/6h, alert
  `ScrapeSuccessBudgetBurnTicket`). A few missed scrapes leave gaps in graphs
  but do not hurt anyone immediately. Losing a target entirely is covered by
  `PrometheusTargetDown` and `SLOMetricsAbsent`, and losing Prometheus by the
  Watchdog.
- Weakness: a target that is down through its own fault spends the
  platform's budget. A production version would count only failures the
  platform is responsible for.

Other SLI types that fit other kinds of services: freshness (age of the
newest processed record) for pipelines, durability for storage, throughput
or queue age for batch systems.

## Capacity: requests versus usage

`rules/capacity-recording.yaml` records CPU and memory requests and actual
usage per namespace, and the ratio between them. The "Platform" dashboard
shows them. They are not an SLO. They show how much reserved capacity sits
unused, which is the main lever on cost in a Kubernetes cluster.

## Known gaps

- Server-side measurement misses requests that never reach the app
  (connection refused, DNS failure, a crashed pod). If no pod is
  scrapeable, the ratios have no data and the burn-rate alerts cannot fire.
  `SLOMetricsAbsent` pages in that case. In production a client-side or
  load-balancer SLI would close this gap.
- With no traffic at all the ratio is 0/0 and has no value. That is the
  correct answer (nothing to measure), but dashboards show "No data".
- All `/work` requests count equally. A real service might weight requests or
  exclude some (e.g. synthetic traffic).
