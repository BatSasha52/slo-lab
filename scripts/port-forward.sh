#!/usr/bin/env bash
# Forward Prometheus, Alertmanager and Grafana to localhost until Ctrl-C.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl

pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

kubectl -n "$MON_NS" port-forward "svc/${KPS_RELEASE}-prometheus" 9090:9090 >/dev/null & pids+=($!)
kubectl -n "$MON_NS" port-forward "svc/${KPS_RELEASE}-alertmanager" 9093:9093 >/dev/null & pids+=($!)
kubectl -n "$MON_NS" port-forward "svc/${KPS_RELEASE}-grafana" 3000:80 >/dev/null & pids+=($!)

password="$(kubectl get secret "${KPS_RELEASE}-grafana" -n "$MON_NS" \
  -o jsonpath='{.data.admin-password}' | base64 -d)"
cat <<INFO
Prometheus:   http://localhost:9090
Alertmanager: http://localhost:9093
Grafana:      http://localhost:3000  (user admin, password ${password})
              SLO dashboard: http://localhost:3000/d/slo-lab-service-slo
Press Ctrl-C to stop.
INFO
wait
