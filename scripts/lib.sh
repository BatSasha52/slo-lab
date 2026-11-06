#!/usr/bin/env bash
# Shared settings and helpers. Sourced by the other scripts, not run directly.
# shellcheck disable=SC2034  # variables are used by the scripts sourcing this

set -euo pipefail

CLUSTER_NAME="slo-lab"
APP_NS="slo-lab"
MON_NS="monitoring"
APP_IMAGE="slo-lab/demo-app:0.1.0"
BASE_IMAGE="python:3.13.15-slim-bookworm"
KPS_RELEASE="kps"
KPS_CHART="oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack"
KPS_CHART_VERSION="92.21.1"

# Under Git Bash the tools are Windows executables, which need C:/... paths;
# `pwd -W` gives that form there and fails harmlessly elsewhere.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && { pwd -W 2>/dev/null || pwd; })"

# Git Bash rewrites arguments that look like POSIX paths (for example the
# API proxy paths passed to `kubectl get --raw`). Turn that off; it has no
# effect outside MSYS.
export MSYS_NO_PATHCONV=1

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }

require() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found on PATH (see README prerequisites)"
  done
}

# Prints the name of a Python 3.11+ interpreter. Checks the version instead of
# trusting the name: on Windows, "python3" can be a Microsoft Store stub.
python_bin() {
  local candidate
  for candidate in python3 python; do
    if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 11))' >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  die "Python 3.11 or newer not found"
}

# GET a path on the in-cluster Prometheus through the Kubernetes API server
# proxy, so no port-forward is needed. Example: prom_get /api/v1/alerts
prom_get() {
  kubectl get --raw "/api/v1/namespaces/${MON_NS}/services/http:${KPS_RELEASE}-prometheus:9090/proxy$1"
}

# Run an instant PromQL query and print the raw JSON response.
prom_query() {
  local encoded
  encoded="$("$(python_bin)" -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  prom_get "/api/v1/query?query=${encoded}"
}

# Print the first value of an instant query result, or "none".
prom_value() {
  prom_query "$1" | "$(python_bin)" -c '
import json, sys
result = json.load(sys.stdin)["data"]["result"]
print(result[0]["value"][1] if result else "none")'
}

# Convert a path for the native tools: C:\... under Git Bash, unchanged elsewhere.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"
}
