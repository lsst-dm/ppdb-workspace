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
- `docs/references.md`: links to external documentation sites and GitHub repositories
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
  current. `notes.md` holds decisions, findings and gotchas by topic, edited
  in place; it isn't a work log. Read all three at session start when working
  a ticket. Scripts and other artifacts don't go here; reusable code goes in
  the relevant component repo.

Put new knowledge at the narrowest level: component gotchas → `.claude/rules/`,
ticket state → `notes/tickets/`, durable system facts → `docs/`, and only
workspace-wide essentials here.

## Related repos (not submodules)

Sibling checkouts in `~/code` if needed: `dax_apdb` (replication source),
`felis` (schema tooling), `ppdb-config` (PPDB YAML configs deployed to
`gs://ppdb-<env>-config`). `dax_ppdbx_gcp` is retired and no longer used;
its helpers now live in `lsst.dax.ppdb.gcp`.

## Conventions

- **Ticket work follows `docs/workflow-tickets.md`.** Read it when starting or
  resuming a ticket.
  - The branch is `tickets/DM-NNNNN`, both in the affected submodules and in
    this workspace.
  - Claude commits, tests and watches CI on its own.
  - Claude **asks before creating any branch or PR**, in this workspace or a
    submodule. Name the branch or PR and wait for a yes.
  - Claude **never switches branches** unless the user says to. Work stays on
    the currently checked-out branch.
  - Claude pushes `tickets/*` branches on its own. It **asks before** force
    pushes, pushes to `main`, tag pushes, `gh pr create` (always as a draft)
    and `gh pr ready`.
  - On a CI failure, Claude reports it and doesn't fix it unless asked.
  - The user picks reviewers and merges. **Claude never merges** (`gh pr merge`
    is denied).
- Work is tracked in Jira (project **DM**). Non-ticket workspace branches use
  `u/JeremyMcCormick/<topic>`.
- Work is committed and pushed in the submodule repos directly. **Ignore
  submodule pointer changes** in this repo (`modified: repos/<name> (new
  commits)`): don't commit them or ask about them.
  - Submodules are set to `ignore = all`, so `git status` and `git diff` don't
    show pointer changes, but they can still end up in a commit. Stage files
    by path (no `commit -a` or `add -A`), and before pushing check that
    `git diff --stat --ignore-submodules=none origin/main...HEAD` lists no
    `repos/` paths. Workspace PRs never include submodule pointers.
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
