# CLAUDE.md

Guidance for Claude Code when working with this repo.

## What This Repo Is

A companion repository for a 10–15 minute Harness "Technical Tidbit" video on **Custom Plugins** (JIRA: PRODEDU-1568).

The tidbit demonstrates the feature in a single concrete workflow a learner can reproduce in their own Harness account. All documentation (README, specs, video script) must stay in parity. See `specs/build.md` for the design rationale and `docs/parity-matrix.md` for the cross-doc change-impact checklist.

## Architecture

(Fill in once `.harness/`, `app/`, and `k8s/` are populated. The exemplar at `~/Code/cd-tidbit-pipeline-control-rollback/CLAUDE.md` is a template for what this section looks like.)

## Common Commands

```bash
make validate          # Pre-flight checks
make cleanup           # Tear down what setup.sh created
make build-local       # Build the plugin image locally
make run-local         # Run the plugin image locally
make port-forward      # Foreground port-forward to Dev + Prod
```

## Key Conventions

- **Parity.** Changes to README demo steps, pipeline YAML, or video script must be reflected across all of them and in `specs/build.md`. See `docs/parity-matrix.md` for the cross-doc change-impact checklist.
- **Three-engine templating** (only relevant if `.harness/` references envsubst placeholders and k8s manifests use Go templating):
  - `${VAR}` — resolved at setup time by `scripts/setup.sh` via `envsubst` (restricted whitelist).
  - `<+...>` — Harness pipeline expressions, resolved at run/deploy time.
  - `{{.Values.x}}` — Go templating in k8s manifests, resolved at deploy time after Harness fills the values.
- **No external dependencies** in the demo app. Prefer stdlib.
- (Add tidbit-specific conventions as the spec firms up.)

## Skill workflow

When iterating on this tidbit, lean on the `harness-tidbit` plugin:

- `/tidbit-spec` — draft or refine `specs/build.md`, README outline, and video script in parity.
- `/tidbit-resources` — regenerate `scripts/setup.sh`, `docs/resource-map.md`, `docs/placeholders.md` from current `.harness/`.
- `/tidbit-parity-check` — audit cross-doc drift before recording.
