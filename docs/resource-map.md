# Harness Resource Map

The single source of truth for **how the `.harness/` resources reference each other**, and **which templating engine owns each token**. Use it to answer "who references this identifier?" and "what resolves this `${...}` / `<+...>` / `{{...}}`?" without grepping every file.

> Keep this in sync when you rename an identifier, add a cross-reference, or change a templated value. Referenced from `CLAUDE.md`.

---

## 1. Identifier registry

Every Harness resource has a stable **identifier** (account-independent — these are *not* templated). Display `name`s may differ from identifiers; both are listed where they diverge.

| Resource | File | `identifier` | `name` |
|---|---|---|---|
| Pipeline | `.harness/pipeline.yaml` | | |
| Service | `.harness/service.yaml` | | |
| (etc.) | | | |

**Load-bearing names** (not free to rename):
- (List anything where the name is referenced by another file or expression — e.g. environment names used in `<+env.name>` expressions.)

---

## 2. Reference graph (who points at whom)

```
pipeline.yaml (<identifier>)
├─ ...
└─ ...

service.yaml (<identifier>)
├─ ...
└─ ...
```

**Provisioning / dependency order** (used by `scripts/setup.sh`):
`project → secrets → connectors → service → environments → infrastructures → pipeline → input sets`. Each resource must exist before anything that references it.

---

## 3. Templating layers — who resolves what

Three engines resolve tokens, in this order. They never overlap; knowing the owner tells you *when* and *by what* a token is replaced.

| Token form | Engine | Resolved when | Resolved by | Example |
|---|---|---|---|---|
| `${VAR}` | **envsubst** | Setup time | `scripts/setup.sh` (restricted var list) | `${HARNESS_ORG}` |
| `<+...>` | **Harness expressions** | Run / deploy time | Harness pipeline engine | `<+pipeline.sequenceId>`, `<+artifact.image>` |
| `{{.Values.x}}` | **Go templating** | Deploy time (after Harness resolves values) | Harness K8s manifest renderer | `{{.Values.image}}` |

### Where each appears

(Fill in once `.harness/` and `k8s/` are populated.)

---

## 4. Quick lookups

**"What references identifier X?"** — see §2 graph.

**"Which file feeds this `${VAR}`?"** — see [placeholders.md](placeholders.md).

**"If I edit a demo step, what else changes?"** — see [parity-matrix.md](parity-matrix.md).
