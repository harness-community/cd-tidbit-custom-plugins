# Narrator Script — Custom Plugins

Read this aloud while performing the actions described in brackets. Each act maps to [production-spec.md](./production-spec.md).

> Version numbers like `<v1>` and column ids like `<dev-col-id>` are illustrative placeholders. Read the real values off the screen at recording time — the demo card you see may have a different id than the one you rehearsed with.

---

## Act 1 — Overview and Setup (2–3 min)

### Narration

>

> (Establish what's on screen: pipeline canvas with three stages (Dev, QA, Prod), Kanboard tab with one task in Backlog, terminal showing the project tree.)

**[On-screen action]**

>

> (Tour the moving parts at a high level — the demo app, the plugin, the Kanboard board — and set up what the viewer will see in the next four acts.)

---

## Act 2 — Tour the plugin and the board (2–3 min)

### Narration

>

> (Open `plugin/entrypoint.py` — point at the import, the env-var reads, and the single `kb.move_task_position` call. Then open `plugin/Dockerfile` — point at `pip install kanboard` and `ENTRYPOINT`.)

>

> (Open `.harness/pipeline.yaml` to the Dev stage's Plugin step — point at `image:`, `settings:`, and especially the `<+secrets.getValue("kanboard_api_token")>` reference and the `KANBOARD_COL: <+env.variables.column_id>` per-env parameter.)

>

> (Switch to the Kanboard tab — show the "Deployments" project, the four columns, and the one task sitting in Backlog.)

**[On-screen action]**

---

## Act 3 — Run the pipeline; Dev stage (2–3 min)

### Narration

>

> (Click Run. Open the pipeline execution view. Wait for the Dev Deploy step to finish — show the Dev browser tab updating to the new badge.)

>

> (Wait for the Dev Plugin step to finish — switch to the Kanboard tab and show the card now in the Dev column. Hover the Plugin step in the execution view to show the env vars actually passed.)

**[On-screen action]**

---

## Act 4 — QA stage (2–3 min)

### Narration

>

> (Pipeline advances to QA. Show the QA Deploy step completing — QA browser tab updates to the orange badge. Show the QA Plugin step completing — Kanboard card hops Dev → QA.)

>

> (Brief callback: same plugin image, different `KANBOARD_COL`. Show by hovering the step's settings in QA vs. Dev side by side if practical.)

**[On-screen action]**

---

## Act 5 — Prod stage (2–3 min)

### Narration

>

> (Pipeline advances to Prod. Prod browser tab updates to green; Kanboard card hops QA → Prod. Pipeline finishes green.)

>

> (Wrap up: recap the five things the viewer just saw — Plugin step, image source, secret reference, ITSM effect, per-env parameter — and point at the "Future Enhancements" section in the README.)

**[On-screen action]**

---

## Closing

> That's Custom Plugins in Harness. Try it yourself — the repo at (REPO URL) has everything you need.
