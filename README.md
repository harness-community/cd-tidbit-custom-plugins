# Custom Plugins

A Harness Technical Tidbit demonstrating **Custom Plugins** — a containerized plugin step that drives an external ITSM workflow (Kanboard) as an app is deployed Dev → QA → Prod.

> 10–15 minute video walkthrough: (link to be added after recording)
>
> Tracking ticket: PRODEDU-1568

## What You'll Learn

After completing this tidbit, you can:

- Build a containerized Harness Plugin step from a Dockerfile in a Harness CI stage.
- Push the plugin image to a registry (GHCR) and reference it from a pipeline.
- Pass per-environment configuration to a single plugin image via env vars.
- Inject Harness secrets into a Plugin step's environment.
- Observe the plugin's effect on an external ITSM system (Kanboard).

## Prerequisites

- Harness account with permission to create Projects, Connectors, Secrets, Services, Environments, Infras, and Pipelines, and with Harness Cloud build credits available.
- A Kubernetes cluster you can `kubectl` into (the Harness delegate, the demo app, and Kanboard all run here).
- `helm`, `kubectl`, `curl`, `envsubst`, `jq`, `yq` installed locally. (No local `docker` — image builds run on Harness Cloud.)
- A GitHub account + a Personal Access Token with `read:packages` + `write:packages` (used as a Harness secret for the GHCR connector and as the cluster's `ghcr-cred` imagePullSecret).

## Repository Structure

```
.
├── README.md            (this file)
├── CLAUDE.md            (conventions for AI assistants)
├── Makefile
├── .env.example
├── app/                 (the Python web app being deployed)
├── plugin/              (the containerized Kanboard plugin)
├── k8s/                 (Kubernetes manifests for the demo app)
├── specs/
│   └── build.md         (design rationale)
├── docs/
│   ├── parity-matrix.md
│   ├── resource-map.md
│   └── placeholders.md
├── video/
│   ├── script.md
│   └── production-spec.md
├── scripts/
│   ├── setup.sh
│   ├── cleanup.sh
│   ├── port-forward.sh
│   └── validate-setup.sh
└── .harness/            (Harness resources — pipeline, connectors, etc.)
```

## Setup

1. **Fork this repo** to your GitHub account.
2. **Clone your fork** locally.
3. **Copy `.env.example` to `.env`** and fill in your Harness and GitHub values. Leave the `KANBOARD_*` keys blank — `setup.sh` populates them.
4. **Run `./scripts/setup.sh`** — creates namespaces, installs the Harness delegate, installs Kanboard via Helm, then bootstraps Kanboard non-interactively: a "Deployments" project is created with columns Backlog / Dev / QA / Prod and a single demo task in Backlog. A random `KANBOARD_API_TOKEN` is generated (injected into the Kanboard pod and into a Harness secret) and the project / column / task IDs are written back into `.env`. The script also provisions the Harness Project / Connectors / Service / Environments / Infras / Pipeline. Re-runs are no-ops.
5. **Run `make port-forward`** — opens local ports to Dev / QA / Prod and to Kanboard (`http://127.0.0.1:8090`, default `admin` / `admin`). Your browser will likely flag the default password as compromised — safe to dismiss for this ephemeral demo cluster; the Kanboard install ships with this default and isn't reachable outside `localhost`.
6. **Build the plugin image in Harness.** In the Harness UI, open the **Build Kanboard Plugin** pipeline and click **Run**. The CI stage builds `ghcr.io/<your-user>/custom-plugins-kanboard:v1` on Harness Cloud and pushes it to GHCR. You only need to do this once (or again whenever `plugin/` changes).
7. **Run `make validate`** — pre-flight checks.

## Run the Demo

The demo is a single pipeline run that marches through Dev → QA → Prod. As each stage's Deploy step completes, that stage's Plugin step moves the demo card to the next column on the Kanboard board.

### Step 1 — Tour the plugin and the board

Before running the pipeline, open three things side by side: the pipeline YAML view (showing the Plugin step's `settings`), `plugin/entrypoint.py`, and the Kanboard browser tab with the demo task sitting in **Backlog**.

### Step 2 — Trigger the pipeline; watch the Build, then the Dev stage

Open the **Build and Deploy Demo App** pipeline and click **Run**. The first stage (**Build App Image**) runs on Harness Cloud, building `ghcr.io/<your-user>/custom-plugins-demo:<run-number>` and pushing it to GHCR. The Dev stage's Deploy step then rolls that tag out into `web-dev`; the Plugin step moves the card from **Backlog → Dev**. The Dev tab at `http://127.0.0.1:8080` shows the new badge and Kanboard shows the card in the Dev column.

### Step 3 — QA stage

The pipeline advances to QA. The card hops **Dev → QA**; the QA tab at `http://127.0.0.1:8081` updates.

### Step 4 — Prod stage

The pipeline advances to Prod. The card hops **QA → Prod**; the Prod tab at `http://127.0.0.1:8082` updates. Pipeline finishes green.

To re-run the demo, drag the card back to Backlog in the Kanboard UI and trigger the pipeline again.

## Future Enhancements

Things the tidbit deliberately omits but a learner might layer in next:

- **Approval gates between stages.** Wrap each Plugin step in a manual approval, or add a Harness Approval step before the Plugin step. Useful for showing that the plugin only fires on confirmed promotions.
- **Pipeline triggered by Kanboard events.** Use a Kanboard plugin or webhook to POST to a Harness Custom Trigger when a card is dragged into a "Ready to Deploy" column — closing the loop in the other direction.
- **Plugin failure handling.** Make the plugin step a non-blocking notification (`failureStrategy: ignore`) so a Kanboard outage doesn't block deploys.
- **One plugin, many ITSM targets.** Add a `TARGET=kanboard|jira|servicenow` env var and switch on it in the entrypoint — same Plugin step shape for all.

## Cleanup

```bash
./scripts/cleanup.sh
```

## Troubleshooting

(Common issues encountered while testing the runbook. Update this as you hit them.)

## Further Reading

- [Harness Plugin step](https://developer.harness.io/docs/continuous-integration/use-ci/use-drone-plugins/run-a-drone-plugin-in-ci/)
- [Kanboard docs](https://docs.kanboard.org/)
- [Kanboard Python client](https://github.com/kanboard/kanboard-api-python)
- [Kanboard Helm chart](https://github.com/kube-the-home/kanboard-helm)
