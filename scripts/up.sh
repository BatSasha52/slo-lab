#!/usr/bin/env bash
# Bring the whole lab up from nothing. Safe to re-run.
dir="$(dirname "$0")"
set -euo pipefail
bash "$dir/cluster-up.sh"
bash "$dir/deploy-monitoring.sh"
bash "$dir/deploy-app.sh"
bash "$dir/smoke-test.sh"
