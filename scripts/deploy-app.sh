#!/usr/bin/env bash
# Build the demo-app image, load it into the kind nodes (there is no
# registry), and apply the manifests under k8s/.
# Requires the monitoring stack for the ServiceMonitor CRD and namespace.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require docker kind kubectl

log "building $APP_IMAGE"
docker build -t "$APP_IMAGE" "$REPO_ROOT/app"
docker image inspect "$BASE_IMAGE" >/dev/null 2>&1 || docker pull "$BASE_IMAGE"

# Export only the local platform. With Docker's containerd image store,
# `kind load docker-image` exports the whole multi-platform index and the
# import fails on the platforms that were never pulled.
log "loading images into kind"
platform="$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}')"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
# Older Docker versions lack --platform; they also use the classic image
# store, where a plain save works.
docker save --platform "$platform" -o "$(native_path "$archive")" "$APP_IMAGE" "$BASE_IMAGE" \
  || docker save -o "$(native_path "$archive")" "$APP_IMAGE" "$BASE_IMAGE"
kind load image-archive "$(native_path "$archive")" --name "$CLUSTER_NAME"

kubectl apply -f "$REPO_ROOT/k8s/namespace.yaml"
if ! kubectl get secret demo-app-admin -n "$APP_NS" >/dev/null 2>&1; then
  log "creating admin token secret"
  token="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  kubectl create secret generic demo-app-admin -n "$APP_NS" --from-literal=token="$token"
fi

log "applying manifests"
kubectl apply -k "$REPO_ROOT/k8s"
# The image tag does not change between local builds, so restart to pick up
# a rebuilt image. maxUnavailable: 0 keeps this from dropping traffic.
kubectl rollout restart deployment/demo-app -n "$APP_NS"
kubectl rollout status deployment/demo-app -n "$APP_NS" --timeout 180s
kubectl rollout status deployment/loadgen -n "$APP_NS" --timeout 180s
kubectl rollout status deployment/alert-receiver -n "$MON_NS" --timeout 180s
kubectl get pods -n "$APP_NS" -o wide
