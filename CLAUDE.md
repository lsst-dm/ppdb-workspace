# PPDB Workspace

Meta-repo for work on the Rubin Observatory **Prompt Products Database (PPDB)**.
It holds no product code itself: the component repos are git submodules under
`repos/`, and this repo carries shared context and cross-repo notes.

## Components

| Submodule | Upstream | Role |
|---|---|---|
| `repos/dax_ppdb` | lsst/dax_ppdb | Core Python package (`lsst.dax.ppdb`): replication, Parquet export, GCS upload, BigQuery promotion. CLIs: `ppdb-cli`, `ppdb-replication`. |
| `repos/ppdb-cloud-functions` | lsst-dm/ppdb-cloud-functions | Cloud Run functions/jobs and Dataflow jobs: `stage_chunk`, `track_chunk`, `promote_chunks`, `load_sso`. |
| `repos/idf_deploy` | lsst/idf_deploy | Terraform for GCP; PPDB in `environment/deployments/ppdb/`. |
| `repos/phalanx` | lsst-sqre/phalanx | Kubernetes app configs; PPDB apps `ppdb-replication` (USDF) and `ppdbtap` (IDF). |
| `repos/sdm_schemas` | lsst/sdm_schemas | Felis schemas: `ppdb.yaml` (built from `apdb.yaml` + `sso_base.yaml`), `dp2_prompt.yaml`; source of BigQuery tables and ppdbtap TAP_SCHEMA. |

Component-specific guidance (build/test, layout, deploy behavior) is in
`.claude/rules/` and loads automatically when working in that repo.

## Data flow (short)

APDB → `ppdb-replication run` (Parquet export, status `exported`) →
`upload-chunks` (GCS, `uploaded`) → `stage_chunk` Dataflow (BigQuery staging,
`staged`) → `promote_chunks` (`ppdb_internal` + `ppdb_public`, `promoted`) → `ppdbtap` (TAP).
Stages are wired by Pub/Sub; all GCP resources are in `idf_deploy`. Most
changes span more than one repo. Read `docs/architecture.md` before
cross-repo work.

## Docs and notes

- `docs/architecture.md`: pipeline diagram, chunk lifecycle, BigQuery datasets, ownership table, cross-repo change checklist
- `docs/glossary.md`: APDB/PPDB terms, environments, facilities
- `docs/workflow-tickets.md`: ticket lifecycle from start to close-out, and
  what Claude does on its own vs. asks first
- `docs/components/<repo>.md`: detailed reference per component. dax_ppdb
  (config, datasets, env vars, pipeline steps, CLIs); ppdb-cloud-functions
  (message contracts, error handling, deploy workflows); idf_deploy and
  phalanx (PPDB resources, per-env values, IAM, secrets); sdm_schemas
  (PPDB schemas, consumers, schema change path)
- `notes/tickets/DM-NNNNN/`: one directory per ticket, copied from
  `notes/tickets/_template/`. `plan.md` holds the goal and approach, and Claude
  asks before changing it. `todo.md` is the checklist, which Claude keeps
  current. `notes.md` is a dated log, which Claude appends to each session.
  Read all three at session start when working a ticket. One-off scripts and
  artifacts don't go here; they go in a component repo or in `ppdb-scripts`.

Put new knowledge at the narrowest level: component gotchas → `.claude/rules/`,
ticket state → `notes/tickets/`, durable system facts → `docs/`, and only
workspace-wide essentials here.

## Related repos (not submodules)

Sibling checkouts in `~/code` if needed: `dax_apdb` (replication source),
`dax_ppdbx_gcp` (GCP helpers dax_ppdb still imports; **being retired**, so
don't build new work on it), `felis` (schema tooling), `ppdb-config`
(PPDB YAML configs deployed to `gs://ppdb-<env>-config`), `ppdb-scripts`.

## Conventions

- **Ticket work follows `docs/workflow-tickets.md`.** Read it when starting or
  resuming a ticket.
  - The branch is `tickets/DM-NNNNN`, both in the affected submodules and in
    this workspace.
  - Claude creates branches, commits, tests and watches CI on its own.
  - Claude **asks before** `git push`, `gh pr create` (always as a draft) and
    `gh pr ready`.
  - On a CI failure, Claude reports it and doesn't fix it unless asked.
  - The user picks reviewers and merges. **Claude never merges** (`gh pr merge`
    is denied).
- Work is tracked in Jira (project **DM**). Non-ticket workspace branches use
  `u/JeremyMcCormick/<topic>`.
- Commit inside the submodule first. Commit submodule pointer bumps in this
  repo at ticket close-out, or when asked.
- Never run Terraform apply, GCP deploys or deletes, or `kubectl apply/delete`.
  `.claude/settings.json` denies them. Opening or updating a PR in
  `ppdb-cloud-functions` deploys to dev, so say so when asking to push there.

## Environments

All repos use the conda env **`ppdb_env`**, except phalanx, which uses
**`phalanx_env`**. Shell state doesn't persist between Bash calls, so prefix
commands with `conda run -n ppdb_env ...` (or `phalanx_env`) instead of
relying on `conda activate`.

### GCP projects

| Env | Project ID | Use for tests? |
|---|---|---|
| dev | `ppdb-dev-5c07` | **Yes.** All tests and experiments run here |
| int | `ppdb-int-6c62` | **No.** Never run tests against int |
| prod | none yet | n/a |

Select the project with `gcloud config set project PROJECT_ID`. Before running
anything that touches GCP (tests, `bq`, `terraform plan`), check the active
project with `gcloud config get-value project`. If it isn't
`ppdb-dev-5c07`, stop and ask instead of switching silently.

Nothing is deployed from local commands. Local `terraform` use is limited to
`plan`/`validate`/`fmt` for review; deploys happen in CI.

## Workspace commands

```bash
git submodule update --init --recursive   # fetch submodules after cloning
git submodule foreach git fetch           # update remotes
git submodule update --remote             # move submodules to upstream main
git submodule foreach 'git status -sb'    # branch/dirty state across repos
```
