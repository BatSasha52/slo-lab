# Postmortem: fault-injection drill, elevated errors and latency on demo-app

- Date: 2026-11-05
- Author: Oleksandr Pryimak
- Status: draft
- Severity: page (both phases)
- SLOs affected: demo-app availability (99.5%), demo-app latency (95% under 300 ms)

This was a planned drill on the local lab cluster, run with
`scripts/drill.sh` using its defaults. The faults were injected on purpose;
the point was to measure how the alerting behaves, not to find a culprit.
All times are UTC and come from the drill's recorded timeline
(`2026-11-05-drill-timeline.log` next to this file) and the alert
receiver's logs (`2026-11-05-drill-notifications.jsonl`, plus later lines read
from the receiver directly). The "responder" was the script itself, which cleared each fault two
minutes after the first page fired.

## Summary

Two faults were injected one after the other. First, 50% of `/work`
requests returned HTTP 500 for 10 minutes 14 seconds. The first page reached
the receiver 8 minutes 32 seconds after the fault started, and all pages had
resolved 29 minutes after the fault was cleared. Second, 400 ms was added to
every `/work` request for 47 minutes 36 seconds. The first latency page fired
45 minutes 16 seconds after the fault started, which matches the
detection time calculated in `docs/slo.md` for a 95% latency objective.

The drill confirmed that the burn-rate alerts, routing, and inhibition work
as designed. It also showed how much a young cluster distorts the long
windows: with only an hour of history, the 6h/30m page fired before the
1h/5m page in the errors phase, and in the latency phase it fired when, with
full history, it would not have fired at all.

## Impact

Errors phase (22:15:20 to 22:25:34):
- About 3,090 of about 8,950 `/work` requests failed (Prometheus
  `increase()` over 22:15 to 22:30, so extrapolated, not an exact count).
- At the steady 10 requests per second, a full 28-day window holds about
  121,000 allowed failures, so this would have used about 2.5% of a real
  monthly budget. The dashboard showed the budget at -947% instead, because
  the "28-day" window only contained the lab's 100 minutes of history (see
  contributing factors).

Latency phase (22:54:21 to 23:41:57):
- Every `/work` request took at least 400 ms, so for the SLO every request
  in that period was bad: about 28,500 of about 28,800 `/work` requests
  (Prometheus `increase()` over the phase, extrapolated).
- A real 28-day latency budget at 10 requests per second is about 1.2
  million slow requests, so this would have used about 2.4% of it.

## Detection

| Phase   | Fault start | First alert pending | First page firing | First page delivered | Time to page |
|---------|-------------|---------------------|-------------------|----------------------|--------------|
| errors  | 22:15:20    | 22:17:07 (ticket, 3d/6h) | 22:23:07 (6h/30m) | 22:23:52 | 8 min 32 s |
| latency | 22:54:21    | 23:01:07 (ticket, 3d/6h) | 23:39:37 (1h/5m)  | 23:40:21 | 46 min 0 s |

"Firing" times are the alert's `activeAt` plus its 2-minute `for`. Times
when an alert resolved are as observed by the drill script, which polls every
15 seconds, so they can be up to 15 seconds late.

Errors phase: `docs/slo.md` predicts that at 50% errors the 1h window crosses
the 14.4x threshold after 8.6 minutes. The 1h/5m condition became true at
22:24:07, 8 minutes 47 seconds after the fault started, which matches. But
the 6h/30m page had already become pending at 22:21:07 and fired first.

Latency phase: the 1h/5m condition became true at 23:37:37, 43 minutes 16
seconds after the fault started. `docs/slo.md` predicts 43.2 minutes, because
even 100% slow requests are only a 20x burn of a 5% budget. The page fired
two minutes later, at 23:39:37. Whether 45 minutes is acceptable for a
complete latency regression is a question about the objective, not about the
alert (see action items).

## Response and recovery

| Phase   | Fault cleared | 1h/5m page resolved | 6h/30m page resolved | Ticket delivered |
|---------|---------------|---------------------|----------------------|------------------|
| errors  | 22:25:34      | 22:30:09            | 22:54:17             | 22:57:51         |
| latency | 23:41:57      | 23:44:01            | 23:54:25             | 23:16:51 (before the page) |

The errors 1h/5m page resolved about 4.5 minutes after the fix, because its 5m
window emptied of errors while the 1h ratio was still high (0.085 at 22:54,
above the 0.072 threshold). This is the short window doing its job.

The errors 6h/30m page took about 29 minutes to resolve, because its 30m
window still held ten minutes of 50% errors (a 30m ratio of up to 17%,
against a 3% threshold) until those minutes aged out.

The latency 1h/5m page resolved 2 minutes after the fix: its threshold is
72%, so the 5m ratio fell below it quickly. The latency 6h/30m page resolved
after 12.5 minutes, but not through its short window. At 23:54 the 30m ratio
was still 0.61; the 6h ratio had dropped to 0.299, just below the 30%
threshold, as the slow period was diluted by the rest of the cluster's
2.5 hours of history.

## Timeline (UTC)

| Time     | Event |
|----------|-------|
| 22:15:20 | 50% error rate injected into both demo-app pods |
| 22:17:07 | AvailabilityBudgetBurnTicket (3d/6h) pending |
| 22:19:07 | AvailabilityBudgetBurnTicket (1d/2h) pending |
| 22:21:07 | AvailabilityBudgetBurnPage (6h/30m) pending |
| 22:23:07 | AvailabilityBudgetBurnPage (6h/30m) firing |
| 22:23:52 | Page delivered to the receiver on `/page` |
| 22:24:07 | AvailabilityBudgetBurnPage (1h/5m) pending; 1h ratio crosses 7.2% |
| 22:25:34 | Fault cleared (simulated responder, 2 minutes after the page) |
| 22:26:07 | AvailabilityBudgetBurnPage (1h/5m) firing, half a minute after the fix |
| 22:28:51 | Second page notification, now listing both windows |
| 22:30:09 | AvailabilityBudgetBurnPage (1h/5m) resolved |
| 22:32:07 | AvailabilityBudgetBurnTicket (3d/6h) firing; not delivered (inhibited) |
| 22:33:51 | Page notification: 1h/5m resolved, 6h/30m still firing |
| 22:34:07 | AvailabilityBudgetBurnTicket (1d/2h) firing; not delivered (inhibited) |
| 22:54:17 | AvailabilityBudgetBurnPage (6h/30m) resolved |
| 22:54:21 | 400 ms latency injected |
| 22:57:51 | Both availability tickets delivered on `/ticket` |
| 22:58:51 | Page "resolved" notification for availability delivered |
| 23:01:07 | LatencyBudgetBurnTicket (3d/6h) pending |
| 23:14:07 | LatencyBudgetBurnTicket (1d/2h) pending |
| 23:16:07 | LatencyBudgetBurnTicket (3d/6h) firing |
| 23:16:51 | Latency ticket delivered on `/ticket` (no page was firing, so nothing inhibited it) |
| 23:29:07 | LatencyBudgetBurnTicket (1d/2h) firing |
| 23:37:37 | LatencyBudgetBurnPage (1h/5m) pending; 1h ratio crosses 72% |
| 23:39:07 | LatencyBudgetBurnPage (6h/30m) pending |
| 23:39:37 | LatencyBudgetBurnPage (1h/5m) firing |
| 23:40:21 | Latency page delivered on `/page` |
| 23:41:07 | LatencyBudgetBurnPage (6h/30m) firing |
| 23:41:57 | Fault cleared |
| 23:44:01 | LatencyBudgetBurnPage (1h/5m) resolved |
| 23:45:21 | Page notification: 1h/5m resolved, 6h/30m still firing |
| 23:54:25 | LatencyBudgetBurnPage (6h/30m) resolved, because the 6h ratio fell below 30% |
| 23:54:27 | Drill finished; all four ticket alerts still firing, as expected for their long windows |

## Root cause and contributing factors

The root cause of the user impact was deliberate: faults set through
`/admin/fault`. The findings below are about the monitoring.

1. **Young cluster, short windows.** Requests had been recorded only since
   about 21:15, an hour before the errors phase. `rate()` over a 6h range
   uses whatever samples exist, so the "6h" window behaved like a 1h window
   and crossed its 3% threshold within minutes, ahead of the 1h/5m page. With
   six full hours of clean history it would have needed about 22 minutes at
   50% errors, and the 1h/5m page would have fired first. The same effect
   made the dashboard show -947% of the 28-day budget remaining, where a
   real 28-day window would show about 97.5% remaining.
2. **A page fired after the fix.** The 1h/5m page went pending at 22:24:07,
   the fault was cleared at 22:25:34, and the page still fired at 22:26:07,
   because its 5m window still contained errors. A responder could reasonably
   be confused by a page arriving after they fixed something. The runbook
   now says to check whether the 5m ratio is already falling.
3. **Alertmanager grouping delays later alerts.** The 1h/5m page began firing
   at 22:26:07 but was delivered at 22:28:51, on the group's next
   `group_interval` (5 minutes after the first notification). This is the
   intended trade-off between noise and latency, but it means the second
   window's page can arrive up to 5 minutes after it fires.
4. **The latency 6h/30m page should not have fired at all.** With six full
   hours of history, 47.6 slow minutes give a 6h ratio of at most 13%, well
   under the 30% threshold. It fired, and later resolved, only because the
   6h window held about 2.5 hours of data. Factor 1 again, in the other
   direction.
5. **Tickets arrived before pages in the latency phase.** The 1x (3d/6h)
   latency ticket fired at 23:16, 24 minutes before any page, and with no
   page firing there was nothing to inhibit it. For a slow-building incident
   the ticket is the earliest signal, which is a reason to read tickets
   promptly rather than leaving them for the next day.

## What went well

- Every expected alert fired, in both phases, and each one resolved on its
  own after the fault was cleared.
- Detection times matched the calculated values in `docs/slo.md` (8.6 minutes
  predicted versus 8 minutes 47 seconds for the 1h errors condition; 43.2 minutes
  versus 43 minutes 16 seconds for the 1h latency condition).
- Inhibition worked: both availability tickets fired at 22:32 and 22:34 but
  were held back until the page resolved, then delivered together at 22:57.
- The short windows made the 1h/5m page resolve 4.5 minutes after the fix
  instead of staying up for most of an hour.

## What went poorly

- The 6h/30m page fired first, so the errors phase did not show the order
  the alert design intends. `docs/slo.md` already described the young-window
  effect, but nothing stopped the drill from running on a cluster with too
  little history.
- The latency page took 45 minutes. Correct for the objective, but slow.

## Other alerts during the drill window

`ScrapeSuccessBudgetBurnTicket` (the platform's own SLO) was firing from
21:46 to 23:51. In the 45 minutes before 21:46 there were 21 failed
scrapes, from Grafana, the controller manager, the scheduler and
kube-state-metrics restarting while the cluster and monitoring stack were
being set up, and from the Thanos store gateway, which crash-looped until its
bucket existed. Measured against less than an hour of scrape history, that
was enough to cross the 0.1% budget thresholds. It is unrelated to demo-app and did not interact with the
drill, because the inhibition rule only matches alerts with the same `slo`
label.

## Where we got lucky

- No other alert was firing for demo-app, so the inhibition rule was tested
  in isolation. An incident overlapping with, for example, `SLOMetricsAbsent`
  would have produced more pages and a less clear picture.

## Action items

| Action | Type | Owner | Tracking |
|--------|------|-------|----------|
| Run future drills only after the cluster has at least 6 hours of history, and say so in the README | process | lab owner | done in README |
| Add to the availability page runbook: a page that arrives just after a mitigation is expected; confirm the 5m ratio is falling before escalating | mitigate | lab owner | done in runbook |
| Decide whether a 95% latency objective is right, or add a faster p99 alert for complete latency regressions (it would have paged in minutes instead of 45) | detect | service owner | open |
| Make the dashboard's budget panel show the data's actual time span, so a young window is not read as a missed SLO | detect | lab owner | open |
