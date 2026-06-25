#!/usr/bin/env bash
#
# cleanup.sh — Tear down everything setup.sh created for the Custom Plugins tidbit.
#
# Profile: cd-k8s
#
# Usage:
#   ./scripts/cleanup.sh
#   ./scripts/cleanup.sh --dry-run   # preview what would be deleted
#   ./scripts/cleanup.sh -y          # skip confirmation prompts
#
set -euo pipefail

DRY_RUN=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -y|--yes) ASSUME_YES=true ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${HARNESS_BASE_URL:-https://app.harness.io}"

info() { echo "  → $1"; }
ok()   { echo "  ✓ $1"; }
warn() { echo "  ⚠ $1"; }
die()  { echo "  ✗ $1" >&2; exit 1; }
step() { echo; echo "=== $1 ==="; }

[ -f "$REPO_ROOT/.env" ] || die ".env not found."
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

confirm() {
  [ "$ASSUME_YES" = true ] && return 0
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

api_delete() {
  local desc="$1" url="$2"
  if [ "$DRY_RUN" = true ]; then
    info "DELETE $url"
    return 0
  fi
  local code
  code=$(curl -sS -o /tmp/_resp -w '%{http_code}' \
    -X DELETE "$url" \
    -H "x-api-key: ${HARNESS_API_KEY}")
  case "$code" in
    2*|404) ok "$desc deleted" ;;
    *) warn "$desc delete returned HTTP $code: $(cat /tmp/_resp)" ;;
  esac
}

# Teardown order is REVERSE of setup: leaf resources first, dependencies last.

step "Confirming"
confirm "Tear down the Custom Plugins tidbit?" || { echo "Aborted."; exit 0; }

step "Pipeline"
# TODO: DELETE the pipeline.

step "Infrastructures"
# TODO: DELETE Dev_Infra, QA_Infra, Prod_Infra.

step "Environments"
# TODO: DELETE Dev, QA, Prod.

step "Service"
# TODO: DELETE custom-plugins-demo.

step "Connectors"
# TODO: DELETE ghcrconn, pipelinedemocluster.

step "Secrets"
# TODO: DELETE ghcr_token, kanboard_url, kanboard_api_token.

step "Kanboard (Helm)"
if [ "$DRY_RUN" = true ]; then
  info "helm uninstall kanboard -n kanboard"
  info "kubectl delete namespace kanboard"
else
  helm uninstall kanboard -n kanboard 2>/dev/null || true
  kubectl delete namespace kanboard --ignore-not-found
  ok "Kanboard uninstalled"
fi

step "Cluster: namespaces"
for ns in web-dev web-qa web-prod; do
  if [ "$DRY_RUN" = true ]; then
    info "kubectl delete namespace $ns"
  else
    kubectl delete namespace "$ns" --ignore-not-found
  fi
done

step "Delegate"
if [ "$DRY_RUN" = true ]; then
  info "helm uninstall $DELEGATE_NAME -n harness-delegate-ng"
else
  helm uninstall "$DELEGATE_NAME" -n harness-delegate-ng 2>/dev/null || true
fi

step "Project"
if confirm "Delete the project ${HARNESS_PROJECT}?"; then
  api_delete "project ${HARNESS_PROJECT}" \
    "${BASE_URL}/ng/api/projects/${HARNESS_PROJECT}?accountIdentifier=${HARNESS_ACCOUNT_ID}&orgIdentifier=${HARNESS_ORG}"
fi

echo
ok "Cleanup complete."
