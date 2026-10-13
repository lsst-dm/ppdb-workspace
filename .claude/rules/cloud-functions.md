---
paths:
  - "repos/ppdb-cloud-functions/**"
---

# ppdb-cloud-functions

One directory per function or job, each with `main.py`, `requirements.txt`,
and usually a `Dockerfile`:

| Dir | Kind | Purpose |
|---|---|---|
| `stage_chunk/` | Cloud Run function + Dataflow flex template (`stage_chunk_beam_job.py`) | Load an uploaded chunk's Parquet from GCS into BigQuery staging tables |
| `track_chunk/` | Cloud Run function | Update a chunk's `status` in the PPDB chunk table |
| `promote_chunks/` | Cloud Run **job** | Promote contiguous staged chunks into `ppdb_internal`/`ppdb_public` (`ChunkPromoter` from dax_ppdb) |
| `load_sso/` | Cloud Run function + Dataflow flex template | Load SSO data into BigQuery |

`README.md` is out of date: it describes only `stage_chunk` and mentions a
Makefile and shell scripts that no longer exist. Trust the workflows.

## Deployment

- Deploys are GitHub Actions in `.github/workflows/<name>-deploy-{dev,int}.yaml`.
- **Dev deploys on pull requests and on push to `main`** when files under
  that function's directory change. Opening a PR here changes the dev GCP project.
- Int deploys are `workflow_dispatch` only.
- Runtime config comes from env vars (`os.environ[...]` at the top of each
  `main.py`), set by the workflow from GitHub environment variables. The GCP
  resources they refer to (topics, buckets, service accounts, datasets) are
  defined in `idf_deploy/environment/deployments/ppdb/services/`.
- `scripts/setup-dev-env.sh` exports dev-project settings for local use.
- Local Python work uses the `ppdb_env` conda env. Nothing is deployed
  locally; deploys happen only through these workflows.

## Dependency on dax_ppdb

Functions pin `lsst-dax-ppdb @ git+https://github.com/lsst/dax_ppdb@cloudrun-vX.Y.Z`.
Keep the pins consistent across functions. The exception today is
`stage_chunk/requirements-dataflow.txt`, which tracks `@main`.

Full reference: `docs/components/ppdb-cloud-functions.md`. Read it before non-trivial changes here.
