#!/usr/bin/env bash
# Control the in-cluster load generator.
#   load.sh <rps>     set the request rate (default deployment runs at 10)
#   load.sh stop      scale the generator to zero
#   load.sh start     scale it back to one replica
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

case "${1:-}" in
  stop)  kubectl scale deployment/loadgen -n "$APP_NS" --replicas=0 ;;
  start) kubectl scale deployment/loadgen -n "$APP_NS" --replicas=1 ;;
  ''|*[!0-9.]*) die "usage: load.sh <rps>|start|stop" ;;
  *)
    kubectl set env deployment/loadgen -n "$APP_NS" RPS="$1"
    kubectl rollout status deployment/loadgen -n "$APP_NS" --timeout 60s
    ;;
esac
