#!/usr/bin/env bash
# Delete the kind cluster and everything in it, including Prometheus data.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
require kind

if cluster_exists; then
  kind delete cluster --name "$CLUSTER_NAME"
else
  log "kind cluster '$CLUSTER_NAME' does not exist"
fi
