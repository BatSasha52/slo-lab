#!/usr/bin/env bash
# The CI checks that need no cluster, for running locally before a push.
# Each check is skipped with a note if its tool is not installed.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT" || exit 1

KUBE_VERSION="1.36.0"
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
failed=()

run() {
  local name="$1" tool="$2"; shift 2
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "skip  $name ($tool not installed)"
    return
  fi
  log "run   $name"
  if "$@"; then log "ok    $name"; else failed+=("$name"); log "FAIL  $name"; fi
}

kubeconform_all() {
  kubectl kustomize k8s | kubeconform -strict -summary \
    -kubernetes-version "$KUBE_VERSION" -schema-location default -schema-location "$CRD_SCHEMAS" - \
  && kubectl kustomize monitoring/thanos | kubeconform -strict -summary     -kubernetes-version "$KUBE_VERSION" -schema-location default -schema-location "$CRD_SCHEMAS" -   && scripts/render-rules.sh | kubeconform -strict -summary \
    -kubernetes-version "$KUBE_VERSION" -schema-location default -schema-location "$CRD_SCHEMAS" -
}

run yamllint yamllint yamllint --strict .
run shellcheck shellcheck shellcheck -x scripts/*.sh
run kubeconform kubeconform kubeconform_all
run "promtool check" promtool promtool check rules rules/*.yaml
run "promtool test" promtool promtool test rules rules/tests/*.test.yaml
run "amtool check" amtool amtool check-config monitoring/alertmanager.yaml
run pytest "$(python_bin)" bash -c "cd app && $(python_bin) -m pytest -q"

if (( ${#failed[@]} > 0 )); then
  die "failed: ${failed[*]}"
fi
log "all checks passed"
