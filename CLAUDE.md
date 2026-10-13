# PPDB Workspace

Meta-repo for work on the Rubin Observatory **Prompt Products Database (PPDB)**.
It holds no product code itself: the component repos are git submodules under
`repos/`, and this repo carries shared context and cross-repo notes.

## Components

| Submodule | Upstream | Role |
|---|---|---|
| `repos/dax_ppdb` | lsst/dax_ppdb | Core Python package (`lsst.dax.ppdb`): PPDB schema/config, APDB→PPDB replication, Parquet export and GCS upload of replica chunks, BigQuery chunk promotion, SSO upload. CLIs: `ppdb-cli`, `ppdb-replication`. |
| `repos/ppdb-cloud-functions` | lsst-dm/ppdb-cloud-functions | GCP Cloud Run functions and Dataflow (Apache Beam) jobs: `stage_chunk`, `track_chunk`, `promote_chunks`, `load_sso`. |
| `repos/idf_deploy` | lsst/idf_deploy | Terraform for GCP. PPDB lives in `environment/deployments/ppdb/` (`cloudsql/`, `services/`, `env/{dev,int}*.tfvars`); applied by `.github/workflows/ppdb-{dev,int,prod}-*-tf.yaml`. |
| `repos/phalanx` | lsst-sqre/phalanx | Kubernetes/Argo CD app configs. PPDB apps: `applications/ppdb-replication` (runs at USDF), `applications/ppdbtap` (TAP service on the BigQuery backend, IDF). |

## Data flow (big picture)

1. **Replication** (`ppdb-replication run`, deployed via phalanx `ppdb-replication`
   at USDF) reads replica chunks from the APDB (`lsst.dax.apdb`) and records them
   in the PPDB (Cloud SQL Postgres).
2. **Upload** (`ppdb-replication upload-chunks`) writes chunks as Parquet and
   uploads them to GCS.
3. **Staging**: Pub/Sub triggers `stage_chunk`, which launches a Dataflow job
   to load the Parquet into BigQuery staging tables; `track_chunk` records
   chunk status.
4. **Promotion**: `promote_chunks` moves staged chunks into the production
   BigQuery tables (logic in `dax_ppdb` `bigquery/chunk_promoter.py`).
5. **Serving**: `ppdbtap` (phalanx) exposes the BigQuery dataset over TAP.

GCP resources for steps 2–4 (buckets, Pub/Sub, Cloud Run, Dataflow templates,
BigQuery datasets, IAM) are defined in `idf_deploy/environment/deployments/ppdb/services/`.
A change to a function's env vars, topics, or permissions usually needs a
matching Terraform change in `idf_deploy`.

## Related repos (not submodules)

Checked out as siblings in `~/code` if needed: `dax_apdb` (APDB, replication
source), `dax_ppdbx_gcp` (GCP helpers that `dax_ppdb` currently depends on;
slated for retirement and archiving, so don't build new work on it), `felis` and
`sdm_schemas` (schema definitions), `ppdb-config`, `ppdb-scripts`.

## Conventions

- Work is tracked in Jira (project **DM**). Branches in component repos are
  `tickets/DM-NNNNN`; workspace-only branches use `u/JeremyMcCormick/<topic>`.
- Commit inside the submodule, then commit the updated submodule pointer in
  this repo only when the workspace should track that revision.
- Do not push, open PRs, or run Terraform/deploy commands without asking.
  `.claude/settings.json` denies the destructive ones outright (push,
  `terraform apply`, GCP deploys/deletes, `kubectl apply/delete`); the user
  runs those.
- `dax_ppdb` is a Science Pipelines package: tests are `pytest` under `tests/`;
  it depends on other `lsst-*` packages (`dax_apdb`, `felis`, `resources`).

## Workspace commands

```bash
git submodule update --init --recursive   # fetch submodules after cloning
git submodule foreach git fetch           # update remotes
git submodule update --remote             # move submodules to upstream main
git submodule foreach 'git status -sb'    # branch/dirty state across repos
```

Open `ppdb.code-workspace` in VS Code for a multi-root view.
