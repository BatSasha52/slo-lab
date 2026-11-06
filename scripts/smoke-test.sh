#!/usr/bin/env bash
# End-to-end checks against a running lab: app endpoints, scraping, rule
# evaluation and alert delivery to the webhook receiver.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

failures=0
check() {
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log "ok    $description"
  else
    log "FAIL  $description"
    failures=$((failures + 1))
  fi
}

app_get() {
  kubectl get --raw "/api/v1/namespaces/${APP_NS}/services/http:demo-app:8080/proxy$1"
}

# Retries for up to $1 seconds, for conditions that need a scrape or rule
# evaluation to happen first.
eventually() {
  local timeout="$1"; shift
  local deadline=$((SECONDS + timeout))
  until "$@"; do
    (( SECONDS < deadline )) || return 1
    sleep 5
  done
}

demo_targets_up() { [[ "$(prom_value 'sum(up{job="demo-app",namespace="slo-lab"})')" == "2" ]]; }
sli_has_data() { [[ "$(prom_value 'slo:sli_error:ratio_rate5m{slo="availability"}')" != "none" ]]; }
rule_groups_loaded() {
  prom_get /api/v1/rules | grep -q '"name":"slo-burn-rate-alerts"'
}
watchdog_in_alertmanager() {
  kubectl get --raw "/api/v1/namespaces/${MON_NS}/services/http:${KPS_RELEASE}-alertmanager:9093/proxy/api/v2/alerts?filter=alertname%3D%22Watchdog%22" \
    | grep -q '"alertname":"Watchdog"'
}
receiver_got_watchdog() {
  kubectl logs -n "$MON_NS" deployment/alert-receiver --tail=200 | grep -q '"channel": "watchdog"'
}

check "demo-app /readyz" app_get /readyz
check "demo-app /healthz" app_get /healthz
check "demo-app /work" app_get /work
check "demo-app /metrics exposes http_requests_total" bash -c \
  "kubectl get --raw /api/v1/namespaces/${APP_NS}/services/http:demo-app:8080/proxy/metrics | grep -q '^http_requests_total'"

check "Prometheus scrapes both demo-app pods" eventually 90 demo_targets_up
check "SLO rule groups loaded" eventually 60 rule_groups_loaded
check "SLI recording rule has data" eventually 120 sli_has_data
check "Watchdog reaches Alertmanager" eventually 120 watchdog_in_alertmanager
check "alert-receiver logged a Watchdog notification" eventually 180 receiver_got_watchdog

if (( failures > 0 )); then
  die "$failures check(s) failed"
fi
log "all checks passed"
