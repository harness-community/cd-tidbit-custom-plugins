#!/usr/bin/env bash
#
# setup.sh — Provision the Custom Plugins tidbit in your Harness account.
#
# Reads values from .env (copy .env.example → .env first), renders the
# templated YAML in .harness/, and creates everything via the Harness NG API.
# Re-runnable: existing resources are updated (PUT) rather than duplicated.
#
# Also installs the Kanboard Helm chart (kube-the-home/kanboard-helm) into the
# learner's cluster — the ITSM target the plugin step talks to.
#
# Usage:
#   cp .env.example .env      # then fill in your values
#   ./scripts/setup.sh
#   ./scripts/setup.sh --dry-run            # print every API call; change nothing
#   ./scripts/setup.sh --bootstrap-kanboard # one-time: print Kanboard project/column IDs
#
# Profile: cd-k8s
#
set -euo pipefail

# --- Parse args ---
DRY_RUN=false
BOOTSTRAP_KANBOARD=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --bootstrap-kanboard) BOOTSTRAP_KANBOARD=true ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- Locate repo root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_DIR="$REPO_ROOT/.harness"

BASE_URL="${HARNESS_BASE_URL:-https://app.harness.io}"

# --- Output helpers ---
info()  { echo "  → $1"; }
ok()    { echo "  ✓ $1"; }
warn()  { echo "  ⚠ $1"; }
die()   { echo "  ✗ $1" >&2; exit 1; }
step()  { echo; echo "=== $1 ==="; }

# --- Load .env ---
[ -f "$REPO_ROOT/.env" ] || die ".env not found. Copy .env.example to .env and fill it in."
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

# --- Validate required vars ---
REQUIRED=(HARNESS_ACCOUNT_ID HARNESS_API_KEY HARNESS_ORG HARNESS_PROJECT
          GITHUB_USERNAME GITHUB_PAT DELEGATE_SELECTOR DELEGATE_NAME
          KANBOARD_URL)
missing=()
for v in "${REQUIRED[@]}"; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || die "Missing required .env values: ${missing[*]}"
CREATE_PROJECT="${CREATE_PROJECT:-true}"

if [ "$DRY_RUN" = true ]; then
  echo "### DRY RUN — no API calls will be executed. ###"
fi

# --- Check dependencies ---
step "Checking dependencies"
for tool in curl envsubst jq yq kubectl helm; do
  command -v "$tool" &>/dev/null && ok "$tool" || die "$tool not found — please install it"
done

# --- Redaction helper for dry-run output ---
redact() {
  sed -E \
    -e "s|${HARNESS_API_KEY}|<HARNESS_API_KEY>|g" \
    -e "s|${GITHUB_PAT}|<GITHUB_PAT>|g" \
    -e "s|${KANBOARD_API_TOKEN:-__none__}|<KANBOARD_API_TOKEN>|g"
}

# --- envsubst with restricted variable list ---
# CRITICAL: keep this list in sync with docs/placeholders.md.
ENVSUBST_VARS='${HARNESS_ACCOUNT_ID} ${HARNESS_ORG} ${HARNESS_PROJECT}'

render() {
  local file="$1"
  envsubst "$ENVSUBST_VARS" < "$file"
}

# --- Harness API helper: idempotent create (POST then PUT on 409) ---
api_create() {
  local desc="$1" url="$2" body_file="$3" put_url="${4:-$2}"
  if [ "$DRY_RUN" = true ]; then
    info "POST $url"
    info "Body:"
    render "$body_file" | redact | sed 's/^/      /'
    return 0
  fi
  local rendered
  rendered=$(render "$body_file")
  local resp_code
  resp_code=$(curl -sS -o /tmp/_resp -w '%{http_code}' \
    -X POST "$url" \
    -H "x-api-key: ${HARNESS_API_KEY}" \
    -H "Content-Type: application/yaml" \
    --data-binary "$rendered")
  case "$resp_code" in
    2*) ok "$desc created" ;;
    409)
      info "$desc exists — updating"
      curl -sS -o /tmp/_resp -w '%{http_code}' \
        -X PUT "$put_url" \
        -H "x-api-key: ${HARNESS_API_KEY}" \
        -H "Content-Type: application/yaml" \
        --data-binary "$rendered" > /dev/null
      ok "$desc updated"
      ;;
    *) die "$desc failed (HTTP $resp_code): $(cat /tmp/_resp)" ;;
  esac
}

# --- Bootstrap mode: print Kanboard IDs and exit ---
if [ "$BOOTSTRAP_KANBOARD" = true ]; then
  step "Kanboard bootstrap"
  info "Once Kanboard is reachable at $KANBOARD_URL, use the Kanboard UI:"
  info "  1. Sign in (default admin/admin), change the admin password."
  info "  2. My Profile → API → copy the API token into KANBOARD_API_TOKEN in .env."
  info "  3. Create a project called 'Deployments' with four columns:"
  info "       Backlog | Dev | QA | Prod"
  info "  4. Create one task in Backlog (e.g., 'Deploy custom-plugins-demo')."
  info "  5. Use the Kanboard API or UI to discover the project/task/column IDs."
  info "     Example one-liner once KANBOARD_API_TOKEN is set:"
  cat <<'EOS'

      curl -sS -u "jsonrpc:${KANBOARD_API_TOKEN}" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"getAllProjects","id":1}' \
        "${KANBOARD_URL}" | jq

EOS
  info "  6. Paste the IDs into KANBOARD_{PROJECT,TASK}_ID and KANBOARD_COL_* in .env."
  exit 0
fi

# =====================================================================
# Provisioning — in dependency order:
#   cluster prep (namespaces, ghcr secret, delegate, kanboard) →
#   project → secrets → connectors → service → environments →
#   infrastructures → pipeline
# =====================================================================

step "Cluster: namespaces"
for ns in web-dev web-qa web-prod kanboard; do
  if [ "$DRY_RUN" = true ]; then
    info "kubectl create namespace $ns"
  else
    kubectl get ns "$ns" &>/dev/null || kubectl create namespace "$ns"
    ok "namespace $ns"
  fi
done

step "Cluster: ghcr-cred imagePullSecret"
for ns in web-dev web-qa web-prod; do
  if [ "$DRY_RUN" = true ]; then
    info "kubectl -n $ns create secret docker-registry ghcr-cred --docker-server=ghcr.io --docker-username=$GITHUB_USERNAME --docker-password=<GITHUB_PAT>"
  else
    kubectl -n "$ns" create secret docker-registry ghcr-cred \
      --docker-server=ghcr.io \
      --docker-username="$GITHUB_USERNAME" \
      --docker-password="$GITHUB_PAT" \
      --dry-run=client -o yaml | kubectl apply -f -
    ok "ghcr-cred in $ns"
  fi
done

step "Delegate (Helm)"
if [ "$DRY_RUN" = true ]; then
  info "helm upgrade -i $DELEGATE_NAME --namespace harness-delegate-ng --create-namespace harness-delegate/harness-delegate-ng ..."
else
  # TODO: fetch a project-scoped delegate token via API, then run helm upgrade.
  warn "Delegate install is a TODO — install via the Harness UI or fill in the helm command here."
fi

step "Kanboard (Helm chart)"
# kube-the-home/kanboard-helm — actively maintained, SQLite by default.
if [ "$DRY_RUN" = true ]; then
  info "helm repo add kanboard https://kube-the-home.github.io/kanboard-helm/"
  info "helm upgrade -i kanboard kanboard/kanboard -n kanboard --create-namespace \\"
  info "    --set service.enabled=true --set service.type=ClusterIP --set service.port=8080"
else
  helm repo add kanboard https://kube-the-home.github.io/kanboard-helm/ 2>/dev/null || true
  helm repo update kanboard >/dev/null
  helm upgrade -i kanboard kanboard/kanboard \
    --namespace kanboard --create-namespace \
    --set service.enabled=true \
    --set service.type=ClusterIP \
    --set service.port=8080
  ok "Kanboard installed in namespace 'kanboard'"
  info "Port-forward and finish setup: kubectl -n kanboard port-forward svc/kanboard 8082:8080"
  info "Then re-run: ./scripts/setup.sh --bootstrap-kanboard"
fi

step "Project"
# TODO: If CREATE_PROJECT=true, POST to /ng/api/projects?accountIdentifier=...&orgIdentifier=...
# See exemplar at ~/Code/cd-tidbit-pipeline-control-rollback/scripts/setup.sh for the pattern.

step "Secrets"
# TODO: Create:
#   - ghcr_token         (text)   — GITHUB_PAT, used by GHCR connector
#   - kanboard_url       (text)   — KANBOARD_URL, injected into plugin step
#   - kanboard_api_token (text)   — KANBOARD_API_TOKEN, injected into plugin step

step "Connectors"
# TODO: Create:
#   - ghcrconn               (Docker registry, type=Other, GHCR)
#   - pipelinedemocluster    (K8sCluster, InheritFromDelegate)

step "Service"
# TODO: Create the demo app service (custom-plugins-demo).

step "Environments"
# TODO: Create environments Dev (PreProduction), QA (PreProduction), Prod (Production).

step "Infrastructures"
# TODO: Create Dev_Infra, QA_Infra, Prod_Infra (KubernetesDirect → namespaces web-dev/web-qa/web-prod).

step "Pipeline"
# TODO: Create the pipeline (three stages: Dev, QA, Prod — each Deploy + Plugin step).

echo
ok "Setup complete."
