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
    2*|404)
      ok "$desc deleted" ;;
    400|500)
      # Harness returns 400 with RESOURCE_NOT_FOUND_EXCEPTION when a parent
      # (e.g. the project) is already gone. Treat as success.
      if grep -q "RESOURCE_NOT_FOUND_EXCEPTION" /tmp/_resp; then
        ok "$desc already gone"
      else
        warn "$desc delete returned HTTP $code: $(cat /tmp/_resp)"
      fi ;;
    *)
      warn "$desc delete returned HTTP $code: $(cat /tmp/_resp)" ;;
  esac
}

step "Confirming"
confirm "Tear down the Custom Plugins tidbit?" || { echo "Aborted."; exit 0; }

ACCT="accountIdentifier=$HARNESS_ACCOUNT_ID"
ORG="orgIdentifier=$HARNESS_ORG"

step "Harness project (cascade)"
# Deleting the project cascades pipelines, environments, infrastructures,
# services, connectors, and secrets. Trying to delete these individually in
# reverse dependency order hits ENTITY_REFERENCE_EXCEPTION / ACTIVE_SERVICE_INSTANCES
# errors that the cascade sidesteps.
api_delete "project ${HARNESS_PROJECT}" \
  "${BASE_URL}/ng/api/projects/${HARNESS_PROJECT}?${ACCT}&${ORG}"

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
# setup.sh installs the chart as release `harness-delegate` in namespace `harness-delegate`.
if [ "$DRY_RUN" = true ]; then
  info "helm uninstall harness-delegate -n harness-delegate"
  info "kubectl delete namespace harness-delegate"
else
  helm uninstall harness-delegate -n harness-delegate 2>/dev/null || true
  kubectl delete namespace harness-delegate --ignore-not-found
fi

echo
ok "Cleanup complete."
