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
#
# Re-runs are no-ops: the script reads .env, only writes back keys that are blank,
# and skips Kanboard bootstrap when a "Deployments" project already exists.
#
# Profile: cd-k8s
#
set -euo pipefail

# --- Parse args ---
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
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

# Generate a Kanboard API token on first run if the learner hasn't supplied one.
# Injected into the Kanboard pod via Helm and consumed by the plugin step.
if [ -z "${KANBOARD_API_TOKEN:-}" ]; then
  KANBOARD_API_TOKEN=$(openssl rand -hex 16)
  export KANBOARD_API_TOKEN
  KANBOARD_API_TOKEN_GENERATED=true
else
  KANBOARD_API_TOKEN_GENERATED=false
fi

if [ "$DRY_RUN" = true ]; then
  echo "### DRY RUN — no API calls will be executed. ###"
fi

# --- Check dependencies ---
step "Checking dependencies"
for tool in curl envsubst jq yq kubectl helm openssl; do
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

# --- .env writer (idempotent): only writes keys whose current value is blank ---
# Usage: env_write KEY VALUE
# Reads $REPO_ROOT/.env, sets KEY=VALUE iff the key exists with an empty value.
# Preserves comments and formatting. No-op (with a "→ KEY already set" note) if the
# key already has a value or doesn't appear in the file.
env_write() {
  local key="$1" value="$2"
  local file="$REPO_ROOT/.env"
  if [ "$DRY_RUN" = true ]; then
    info "[.env] $key=$value"
    return 0
  fi
  if ! grep -q "^${key}=" "$file"; then
    warn ".env has no '${key}=' line — skipping (add the key to .env.example first)"
    return 0
  fi
  if grep -q "^${key}=." "$file"; then
    info "$key already set in .env — leaving as-is"
    return 0
  fi
  # macOS sed needs -i ''; the .bak suffix is portable and we delete the backup.
  sed -i.bak "s|^${key}=$|${key}=${value}|" "$file"
  rm -f "${file}.bak"
  ok "$key written to .env"
}

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
# API_AUTHENTICATION_TOKEN is injected via application.env[] so the plugin step
# can authenticate as the reserved `jsonrpc` user without a UI-generated token.
if [ "$DRY_RUN" = true ]; then
  info "helm repo add kanboard https://kube-the-home.github.io/kanboard-helm/"
  info "helm upgrade -i kanboard kanboard/kanboard -n kanboard --create-namespace \\"
  info "    --set service.{enabled=true,type=ClusterIP,port=8080} \\"
  info "    --set-string application.env[0].name=API_AUTHENTICATION_TOKEN \\"
  info "    --set-string application.env[0].value=<KANBOARD_API_TOKEN>"
else
  helm repo add kanboard https://kube-the-home.github.io/kanboard-helm/ 2>/dev/null || true
  helm repo update kanboard >/dev/null
  helm upgrade -i kanboard kanboard/kanboard \
    --namespace kanboard --create-namespace \
    --set service.enabled=true \
    --set service.type=ClusterIP \
    --set service.port=8080 \
    --set-string "application.env[0].name=API_AUTHENTICATION_TOKEN" \
    --set-string "application.env[0].value=${KANBOARD_API_TOKEN}" >/dev/null
  ok "Kanboard chart applied in namespace 'kanboard'"
  info "Waiting for Kanboard rollout…"
  kubectl -n kanboard rollout status deploy/kanboard --timeout=120s >/dev/null
  ok "Kanboard pod ready"
fi

step "Kanboard bootstrap (project / columns / task)"
# Idempotent JSON-RPC bootstrap. Uses admin:admin basic auth over a transient
# port-forward (admin password defaults to 'admin' on a fresh install — never
# leaves localhost). The plugin step at run-time uses the env-injected
# API_AUTHENTICATION_TOKEN as the `jsonrpc` reserved user; it never sees admin.
KB_PROJECT_NAME="Deployments"
KB_TASK_TITLE="Deploy custom-plugins-demo"
KB_COL_NAMES=(Backlog Dev QA Prod)

if [ "$DRY_RUN" = true ]; then
  info "kubectl -n kanboard port-forward svc/kanboard 18090:8080 (background)"
  info "POST createProject {name: '$KB_PROJECT_NAME'} → KANBOARD_PROJECT_ID"
  info "POST getColumns → 4 column ids"
  info "POST updateColumn x4 → rename to ${KB_COL_NAMES[*]}"
  info "POST createTask {title: '$KB_TASK_TITLE'} → KANBOARD_TASK_ID"
  info "Write KANBOARD_PROJECT_ID, KANBOARD_TASK_ID, KANBOARD_COL_* to .env"
else
  # Background port-forward to localhost so we can hit JSON-RPC from the script.
  # The plugin step itself uses the in-cluster KANBOARD_URL — this forward is
  # bootstrap-only and torn down on exit.
  kubectl -n kanboard port-forward svc/kanboard 18090:8080 >/tmp/_kb_pf.log 2>&1 &
  KB_PF_PID=$!
  trap 'kill ${KB_PF_PID} 2>/dev/null || true' EXIT
  # Wait for the forward to accept connections.
  for _ in {1..20}; do
    curl -sS -o /dev/null -w '' http://127.0.0.1:18090/ 2>/dev/null && break
    sleep 0.5
  done

  KB_RPC=http://127.0.0.1:18090/jsonrpc.php
  kb_rpc() {
    # Usage: kb_rpc METHOD '{"k":"v"}'  →  prints the JSON-RPC `result` (raw via jq)
    local method="$1" params="$2"
    curl -sS -u "admin:admin" -H 'Content-Type: application/json' "$KB_RPC" \
      -d "$(jq -nc --arg m "$method" --argjson p "$params" \
            '{jsonrpc:"2.0",id:1,method:$m,params:$p}')" \
      | jq -r '.result'
  }

  # Step 1: ensure the project exists. getProjectByName returns `false` if
  # absent and an object {id, name, ...} when present.
  PROJ=$(kb_rpc getProjectByName "{\"name\":\"$KB_PROJECT_NAME\"}")
  if [ "$PROJ" = "false" ] || [ "$PROJ" = "null" ] || [ -z "$PROJ" ]; then
    PROJ_ID=$(kb_rpc createProject "{\"name\":\"$KB_PROJECT_NAME\"}")
    ok "Project '$KB_PROJECT_NAME' created (id=$PROJ_ID)"
  else
    PROJ_ID=$(jq -r '.id' <<<"$PROJ")
    info "Project '$KB_PROJECT_NAME' exists (id=$PROJ_ID)"
  fi

  # Step 2: rename the 4 default columns by position.
  COLS=$(kb_rpc getColumns "{\"project_id\":$PROJ_ID}")
  for i in 0 1 2 3; do
    COL_ID=$(jq -r ".[$i].id" <<<"$COLS")
    CUR_TITLE=$(jq -r ".[$i].title" <<<"$COLS")
    DESIRED="${KB_COL_NAMES[$i]}"
    if [ "$CUR_TITLE" = "$DESIRED" ]; then
      info "column $((i+1)) already '$DESIRED' (id=$COL_ID)"
    else
      kb_rpc updateColumn "{\"column_id\":$COL_ID,\"title\":\"$DESIRED\"}" >/dev/null
      ok "column $((i+1)) renamed '$CUR_TITLE' → '$DESIRED' (id=$COL_ID)"
    fi
    eval "COL_${DESIRED}_ID=$COL_ID"
  done

  # Step 3: ensure the demo task exists in the Backlog column.
  TASKS=$(kb_rpc getAllTasks "{\"project_id\":$PROJ_ID,\"status_id\":1}")
  TASK_ID=$(jq -r --arg t "$KB_TASK_TITLE" '.[] | select(.title==$t) | .id' <<<"$TASKS" | head -1)
  if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    TASK_ID=$(kb_rpc createTask \
      "{\"project_id\":$PROJ_ID,\"title\":\"$KB_TASK_TITLE\",\"column_id\":${COL_Backlog_ID}}")
    ok "task '$KB_TASK_TITLE' created (id=$TASK_ID)"
  else
    info "task '$KB_TASK_TITLE' exists (id=$TASK_ID)"
  fi

  # Step 4: write captured IDs back into .env (only blank keys are filled).
  env_write KANBOARD_PROJECT_ID "$PROJ_ID"
  env_write KANBOARD_TASK_ID    "$TASK_ID"
  env_write KANBOARD_COL_BACKLOG "$COL_Backlog_ID"
  env_write KANBOARD_COL_DEV     "$COL_Dev_ID"
  env_write KANBOARD_COL_QA      "$COL_QA_ID"
  env_write KANBOARD_COL_PROD    "$COL_Prod_ID"

  # If we generated the token on this run, persist it too.
  if [ "$KANBOARD_API_TOKEN_GENERATED" = true ]; then
    env_write KANBOARD_API_TOKEN "$KANBOARD_API_TOKEN"
    info "Generated KANBOARD_API_TOKEN written to .env"
  fi

  # Tear down the bootstrap port-forward; the plugin step uses the in-cluster URL.
  kill ${KB_PF_PID} 2>/dev/null || true
  trap - EXIT
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
