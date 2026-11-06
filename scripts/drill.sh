#!/usr/bin/env bash
# Incident drill: inject a fault, record when each SLO alert goes pending and
# firing, clear the fault after a simulated response delay, and record when
# the pages resolve. Everything is written with UTC timestamps to
# drill-output/<start time>/ for use in the postmortem.
#
#   drill.sh                 errors phase, then latency phase
#   PHASES=errors drill.sh   one phase only
#
# Settings (environment variables):
#   ERROR_RATE=0.5        fraction of /work requests that fail in the errors phase
#   LATENCY_MS=400        added latency in the latency phase (SLO threshold is 300 ms)
#   RESPONSE_DELAY=120    seconds between the first page firing and the fault being cleared
#   FIRE_TIMEOUT=3600     give up if no page fires within this many seconds
#   RESOLVE_TIMEOUT=1800  give up if the pages have not resolved within this many seconds
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

PHASES="${PHASES:-errors latency}"
ERROR_RATE="${ERROR_RATE:-0.5}"
LATENCY_MS="${LATENCY_MS:-400}"
RESPONSE_DELAY="${RESPONSE_DELAY:-120}"
FIRE_TIMEOUT="${FIRE_TIMEOUT:-3600}"
RESOLVE_TIMEOUT="${RESOLVE_TIMEOUT:-1800}"
POLL_SECONDS=15

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
out_dir="$REPO_ROOT/drill-output/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out_dir"
timeline="$out_dir/timeline.log"
PY="$(python_bin)"

record() {
  local line
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ)  $*"
  echo "$line" | tee -a "$timeline" >&2
}

# One line per active demo-app alert: "<name>/<long_window>/<severity> <state> ...".
# Alerts about other components are left out to keep the timeline readable;
# Prometheus keeps the full history in the ALERTS series.
alert_states() {
  prom_get /api/v1/alerts | "$PY" -c '
import json, sys
for a in json.load(sys.stdin)["data"]["alerts"]:
    labels = a["labels"]
    if labels.get("service") != "demo-app":
        continue
    key = "/".join([labels["alertname"], labels.get("long_window", "-"), labels["severity"]])
    since = a.get("activeAt", "?")[:19]
    print(key, a["state"], "active_since=" + since + "Z")
' | sort
}

declare -A last_state=()

# Polls alert states and records every transition. Returns 0 as soon as the
# condition function passes, 1 on timeout.
watch_until() {
  local condition="$1" timeout="$2"
  local deadline=$((SECONDS + timeout))
  local states key state seen
  while true; do
    # A failed poll must not look like "no alerts", or a transient API error
    # would be recorded as every alert resolving.
    if ! states="$(alert_states)"; then
      record "warn     could not read alerts from Prometheus; retrying"
      (( SECONDS < deadline )) || return 1
      sleep "$POLL_SECONDS"
      continue
    fi
    declare -A current=()
    while read -r key state rest; do
      [[ -n "$key" ]] || continue
      current[$key]="$state"
      if [[ "${last_state[$key]:-inactive}" != "$state" ]]; then
        record "alert    $key ${last_state[$key]:-inactive} -> $state ($rest)"
      fi
    done <<< "$states"
    for seen in "${!last_state[@]}"; do
      if [[ -z "${current[$seen]:-}" ]]; then
        record "alert    $seen ${last_state[$seen]} -> inactive"
      fi
    done
    last_state=()
    for key in "${!current[@]}"; do last_state[$key]="${current[$key]}"; done
    unset current

    if "$condition" "$states"; then return 0; fi
    (( SECONDS < deadline )) || return 1
    sleep "$POLL_SECONDS"
  done
}

snapshot() {
  local slo="$1"
  record "metrics  $slo ratio_5m=$(prom_value "slo:sli_error:ratio_rate5m{slo=\"$slo\"}")" \
    "ratio_1h=$(prom_value "slo:sli_error:ratio_rate1h{slo=\"$slo\"}")" \
    "budget_remaining=$(prom_value "slo:error_budget_remaining:ratio{slo=\"$slo\"}")"
}

run_phase() {
  local slo="$1" page_alert="$2"; shift 2
  local fault_args=("$@")

  page_firing() { grep -q "^${page_alert}/.* firing" <<< "$1"; }
  pages_clear() { ! grep -q "^${page_alert}/" <<< "$1"; }

  record "phase    $slo: starting"
  if ! watch_until pages_clear 60; then
    die "$page_alert is already active; wait for it to resolve before drilling"
  fi
  snapshot "$slo"

  record "event    inject fault: fault.sh ${fault_args[*]}"
  bash "$(dirname "$0")/fault.sh" "${fault_args[@]}" | tee -a "$timeline" >&2

  if ! watch_until page_firing "$FIRE_TIMEOUT"; then
    record "result   $page_alert did not fire within ${FIRE_TIMEOUT}s"
    bash "$(dirname "$0")/fault.sh" clear >/dev/null
    return 1
  fi
  record "event    first $page_alert firing; simulated responder acts in ${RESPONSE_DELAY}s"
  snapshot "$slo"

  local respond_at=$((SECONDS + RESPONSE_DELAY))
  always_false() { return 1; }
  while (( SECONDS < respond_at )); do
    watch_until always_false 0 || true
    sleep "$POLL_SECONDS"
  done

  record "event    mitigate: fault.sh clear"
  bash "$(dirname "$0")/fault.sh" clear | tee -a "$timeline" >&2

  if ! watch_until pages_clear "$RESOLVE_TIMEOUT"; then
    record "result   $page_alert still active after ${RESOLVE_TIMEOUT}s"
    return 1
  fi
  record "event    all $page_alert alerts resolved"
  snapshot "$slo"
}

record "drill    started; phases: $PHASES"
for phase in $PHASES; do
  case "$phase" in
    errors)  run_phase availability AvailabilityBudgetBurnPage errors "$ERROR_RATE" ;;
    latency) run_phase latency LatencyBudgetBurnPage latency "$LATENCY_MS" ;;
    *) die "unknown phase: $phase" ;;
  esac
done

record "drill    finished; still active: $(alert_states | tr '\n' ';')"
kubectl logs -n "$MON_NS" deployment/alert-receiver --since-time="$started_at" \
  | grep -v '"channel": "watchdog"' > "$out_dir/notifications.jsonl" || true
log "timeline:      $timeline"
log "notifications: $out_dir/notifications.jsonl"
