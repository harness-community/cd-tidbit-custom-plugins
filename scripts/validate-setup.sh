#!/usr/bin/env bash
#
# validate-setup.sh — Pre-flight checks before running setup.sh.
#
# Profile: cd-k8s
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
WARN=0
FAIL=0

ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠ $1"; WARN=$((WARN+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
step() { echo; echo "=== $1 ==="; }

step "Required tools"
for tool in curl envsubst jq yq kubectl helm docker; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool"
  else
    fail "$tool not found — install it"
  fi
done

step ".env"
if [ -f "$REPO_ROOT/.env" ]; then
  ok ".env exists"
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
  REQUIRED=(
    HARNESS_ACCOUNT_ID HARNESS_API_KEY HARNESS_ORG HARNESS_PROJECT
    GITHUB_USERNAME GITHUB_PAT
    DELEGATE_SELECTOR DELEGATE_NAME
    KANBOARD_URL
  )
  for v in "${REQUIRED[@]}"; do
    if [ -n "${!v:-}" ]; then
      ok "$v set"
    else
      fail "$v not set in .env"
    fi
  done
  # KANBOARD_API_TOKEN and KANBOARD_*_ID/COL_* are filled in by the
  # --bootstrap-kanboard pass of setup.sh; warn but don't fail if empty.
  for v in KANBOARD_API_TOKEN KANBOARD_PROJECT_ID KANBOARD_TASK_ID \
           KANBOARD_COL_BACKLOG KANBOARD_COL_DEV KANBOARD_COL_QA KANBOARD_COL_PROD; do
    if [ -n "${!v:-}" ]; then
      ok "$v set"
    else
      warn "$v empty — run setup.sh --bootstrap-kanboard after installing Kanboard"
    fi
  done
else
  fail ".env not found — copy .env.example to .env and fill it in"
fi

step "Cluster"
if kubectl cluster-info &>/dev/null; then
  ok "kubectl can reach a cluster"
  for ns in web-dev web-qa web-prod kanboard; do
    if kubectl get ns "$ns" &>/dev/null; then
      ok "namespace $ns exists"
    else
      warn "namespace $ns missing — setup.sh will create it"
    fi
  done
  if kubectl -n harness-delegate-ng get deployment 2>/dev/null | grep -q '.'; then
    ok "delegate present in harness-delegate-ng"
  else
    warn "no delegate detected — setup.sh will install one"
  fi
else
  fail "kubectl cannot reach a cluster"
fi

echo
echo "Pass: $PASS  Warn: $WARN  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
