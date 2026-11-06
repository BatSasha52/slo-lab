#!/usr/bin/env bash
# Inject or clear faults in every running demo-app pod.
#   fault.sh errors <rate>    return HTTP 500 on this fraction of /work, e.g. 0.5
#   fault.sh latency <ms>     add this many milliseconds to every /work request
#   fault.sh clear            remove all faults
#   fault.sh show             print the current setting of each pod
# Each command replaces the previous setting. Fault state lives in process
# memory, so a restarted pod comes back healthy.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

case "${1:-}" in
  errors)  [[ $# -eq 2 ]] || die "usage: fault.sh errors <rate>";  args=(set --error-rate "$2") ;;
  latency) [[ $# -eq 2 ]] || die "usage: fault.sh latency <ms>";   args=(set --latency-ms "$2") ;;
  clear)   args=(clear) ;;
  show)    args=(show) ;;
  *) die "usage: fault.sh errors <rate> | latency <ms> | clear | show" ;;
esac

pods="$(kubectl get pods -n "$APP_NS" -l app.kubernetes.io/name=demo-app \
  --field-selector=status.phase=Running -o name)"
[[ -n "$pods" ]] || die "no running demo-app pods"

for pod in $pods; do
  printf '%s: ' "${pod#pod/}"
  kubectl exec -n "$APP_NS" "$pod" -c demo-app -- python -m slo_app.faultctl "${args[@]}"
done
