# Video Production Spec

This spec defines the structure, timing, and shot list for the Technical Tidbit video on **Custom Plugins**. It is a production reference — what to show, in what order, and how long each segment should take.

For the narrator's spoken script and step-by-step demonstration actions, see [script.md](./script.md).

For the overall demo design, learning objectives, and implementation details, see [build.md](../specs/build.md).

---

## Format

- **Length:** 10–15 minutes
- **Style:** Screen recording with voiceover narration
- **Resolution:** 1920x1080 minimum
- **Framing:** Five coordinate sub-skills of the Plugin step, demonstrated in the order they appear when running a real deployment: the step itself, the image source, secret injection, the ITSM effect, and per-environment parameterization.

---

## Act Structure

| Act | Title | Duration | Features Demonstrated |
|-----|-------|----------|----------------------|
| 1 | Overview and Setup | 2–3 min | Context: pipeline canvas, Kanboard board, what the viewer is about to see |
| 2 | Tour the plugin and the board | 2–3 min | Plugin image source · Harness secret reference · Per-environment parameter |
| 3 | Run the pipeline; Dev stage | 2–3 min | Plugin step (containerized) · ITSM state change (Backlog → Dev) |
| 4 | QA stage | 2–3 min | Per-environment parameter · ITSM state change (Dev → QA) |
| 5 | Prod stage | 2–3 min | ITSM state change (QA → Prod) · recap of all five features |

---

## Act 1 — Overview and Setup

**Purpose:** Orient the viewer. Show what exists, set expectations.

### Shots

1. **Pipeline canvas, full** — three stages visible: Dev, QA, Prod.
2. **Kanboard tab, full board** — "Deployments" project, four columns, one task sitting in Backlog.
3. **Terminal** — project tree (`ls`).

### Key Callouts

- The three pipeline stages map one-to-one to the three Kanboard columns past Backlog.
- The plugin runs once per stage; same image, different config.

---

## Act 2 — Tour the plugin and the board

**Purpose:** Show what the plugin IS (image + code) and how the pipeline wires it up.

### Shots

1. **Editor: `plugin/entrypoint.py`** — highlight env-var reads (3 lines) and the `kb.move_task_position()` call.
2. **Editor: `plugin/Dockerfile`** — highlight `pip install kanboard` and `ENTRYPOINT`.
3. **Harness UI: pipeline YAML view, Dev stage Plugin step** — highlight `image:`, the `<+secrets.getValue("kanboard_api_token")>` reference, and `KANBOARD_COL: <+env.variables.column_id>`.
4. **Kanboard browser tab** — pan across the four columns; settle on the Backlog card.

### Key Callouts

- The plugin is 30 lines of Python in a 4-line Dockerfile. Plugins don't have to be complicated.
- The secret reference syntax (`<+secrets.getValue(...)>`) is the standard Harness pattern — works for any step type, not just plugins.
- `<+env.variables.column_id>` is how the *same* image targets a *different* column in each stage.

---

## Act 3 — Run the pipeline; Dev stage

**Purpose:** First end-to-end payoff. Plugin step actually moves something.

### Shots

1. **Run button click** in the pipeline canvas.
2. **Execution view** — stages advancing, Dev Deploy step ✓.
3. **Dev browser tab at `http://127.0.0.1:8080`** — refresh; new blue badge and version visible.
4. **Execution view** — Dev Plugin step ✓; click into it; show the env vars in the step's input/output.
5. **Kanboard tab** — card now in the Dev column. Optional zoom on the moved card.

### Key Callouts

- The Plugin step succeeded with a 0 exit code; the proof is in Kanboard, not in the step logs.
- The execution view shows what env vars Harness actually injected — useful when debugging.

---

## Act 4 — QA stage

**Purpose:** Reinforce the per-environment parameter point.

### Shots

1. **Execution view** — QA Deploy step ✓.
2. **QA browser tab at `http://127.0.0.1:8081`** — orange badge.
3. **Execution view** — QA Plugin step ✓; hover the step's `settings` to compare `KANBOARD_COL` against Dev's value.
4. **Kanboard tab** — card hops from Dev to QA.

### Key Callouts

- Same plugin image. Different `KANBOARD_COL`. Different result. This is the lesson.
- The `<+env.variables.column_id>` expression resolves *per stage*, not per pipeline.

---

## Act 5 — Prod stage

**Purpose:** Close the loop; recap; point at next steps.

### Shots

1. **Execution view** — Prod Deploy ✓; Prod Plugin ✓; pipeline finishes green.
2. **Prod browser tab at `http://127.0.0.1:8082`** — green badge.
3. **Kanboard tab** — card now in Prod column. Pan across all four columns to show the journey.
4. **README "Future Enhancements" section** in editor or browser.

### Key Callouts

- Five things demonstrated, in the order they appear: Plugin step → image source → secret reference → ITSM effect → per-env parameter.
- The README's "Future Enhancements" section is where viewers go for "what next" (approvals, Kanboard-triggered pipelines, multiple ITSM targets).

---

## Production Notes

- **Wait for pods to roll** before cutting to the per-env browser tab refresh — pre-roll state on screen is confusing.
- **Don't show real account IDs, PATs, or API tokens.** If the Harness UI shows the account id in the URL, blur or crop. PAT and Kanboard token are visible during initial setup only; record those segments with placeholder values.
- **Browser zoom:** 110–125% for readability of the Kanboard UI and the Harness YAML editor.
- **Terminal font:** 16pt+.
- **Kanboard tab placement:** keep Kanboard in a fixed split or fixed monitor position throughout — viewers should never have to hunt for it when the card moves.
- **Reset state before recording:** card in Backlog, Dev/QA/Prod browser tabs at the pre-deploy version.
- **Pause for emphasis** at the moment each card-hop happens — that's the visual payoff.
