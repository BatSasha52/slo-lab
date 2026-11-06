#!/usr/bin/env bash
# Create the kind cluster if it does not exist yet.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require docker kind kubectl

if cluster_exists; then
  log "kind cluster '$CLUSTER_NAME' already exists"
else
  log "creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$REPO_ROOT/kind/cluster.yaml" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null
kubectl get nodes
