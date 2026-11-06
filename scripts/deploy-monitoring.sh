#!/usr/bin/env bash
# Install or upgrade kube-prometheus-stack, then apply the Alertmanager config,
# the SLO and meta rules, and the dashboards from this repository.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl helm

kubectl create namespace "$MON_NS" --dry-run=client -o yaml | kubectl apply -f -

# Must exist before the Alertmanager pod starts (useExistingSecret in the values).
log "applying Alertmanager config"
kubectl create secret generic alertmanager-slo-lab -n "$MON_NS" \
  --from-file=alertmanager.yaml="$REPO_ROOT/monitoring/alertmanager.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

values=(--values "$REPO_ROOT/monitoring/kube-prometheus-stack-values.yaml")
# Once deploy-thanos.sh has run, keep the sidecar on every later upgrade.
if kubectl get secret thanos-objstore -n "$MON_NS" >/dev/null 2>&1; then
  log "Thanos is installed; including monitoring/thanos-values.yaml"
  values+=(--values "$REPO_ROOT/monitoring/thanos-values.yaml")
fi

log "installing $KPS_CHART $KPS_CHART_VERSION (first run takes a few minutes)"
helm upgrade --install "$KPS_RELEASE" "$KPS_CHART" \
  --version "$KPS_CHART_VERSION" \
  --namespace "$MON_NS" \
  "${values[@]}" \
  --wait --timeout 15m

log "applying rules"
bash "$(dirname "$0")/render-rules.sh" | kubectl apply -f -

log "applying dashboards"
kubectl create configmap slo-lab-dashboards -n "$MON_NS" \
  --from-file="$REPO_ROOT/dashboards" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f -

kubectl get pods -n "$MON_NS"
