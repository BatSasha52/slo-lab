#!/usr/bin/env bash
# Print every rules/*.yaml file wrapped in a PrometheusRule resource.
# The plain rule files stay the single source of truth so promtool can check
# and unit-test exactly what gets deployed.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

for file in "$REPO_ROOT"/rules/*.yaml; do
  name="slo-lab-$(basename "$file" .yaml)"
  cat <<HEADER
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: $name
  namespace: $MON_NS
  labels:
    app.kubernetes.io/part-of: slo-lab
spec:
HEADER
  sed 's/^/  /' "$file"
done
