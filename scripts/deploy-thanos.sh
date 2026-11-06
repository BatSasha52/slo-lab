#!/usr/bin/env bash
# Optional: add Thanos (sidecar, store gateway, query) with SeaweedFS as S3
# object storage. Run after scripts/up.sh. Restarts Prometheus once to add
# the sidecar.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kubectl helm

# Generated per cluster instead of being committed. Both the object store and
# Thanos read them from Secrets.
if ! kubectl get secret thanos-objstore -n "$MON_NS" >/dev/null 2>&1; then
  log "creating object storage credentials"
  access_key="thanos"
  secret_key="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  kubectl create secret generic seaweedfs-s3-config -n "$MON_NS" \
    --from-literal=s3.json="{\"identities\":[{\"name\":\"thanos\",\"credentials\":[{\"accessKey\":\"${access_key}\",\"secretKey\":\"${secret_key}\"}],\"actions\":[\"Admin\",\"Read\",\"Write\",\"List\",\"Tagging\"]}]}"
  kubectl create secret generic thanos-objstore -n "$MON_NS" --from-literal=objstore.yml="type: S3
config:
  bucket: thanos
  endpoint: seaweedfs.${MON_NS}.svc:8333
  insecure: true
  access_key: ${access_key}
  secret_key: ${secret_key}
"
fi

log "deploying object storage, store gateway and query"
kubectl apply -k "$REPO_ROOT/monitoring/thanos"
kubectl rollout status deployment/seaweedfs -n "$MON_NS" --timeout 180s
kubectl wait --for=condition=complete job/seaweedfs-create-bucket -n "$MON_NS" --timeout 180s

# deploy-monitoring.sh adds monitoring/thanos-values.yaml because the
# thanos-objstore Secret now exists.
bash "$(dirname "$0")/deploy-monitoring.sh"

kubectl rollout status statefulset/prometheus-kps-prometheus -n "$MON_NS" --timeout 300s
kubectl rollout status statefulset/thanos-store -n "$MON_NS" --timeout 180s
kubectl rollout status deployment/thanos-query -n "$MON_NS" --timeout 180s
log "Thanos Query: kubectl -n $MON_NS port-forward svc/thanos-query 10902:10902, then http://localhost:10902"
