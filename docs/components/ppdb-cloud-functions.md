# ppdb-cloud-functions reference

`repos/ppdb-cloud-functions`. Written from a code survey at `b4b4ed7` (2026-10-13).
The repo `README.md` is stale; this doc and the workflows are more accurate.

## Units

| Dir | GCP resource (name) | Trigger | Entry point |
|---|---|---|---|
| `stage_chunk/` | Cloud Run function `stage-chunk` | Push subscription `stage-chunk` on `stage-chunk-topic` | `stage_chunk(event)` |
| `track_chunk/` | Cloud Run function `track-chunk` | Eventarc on `track-chunk-topic` | `track_chunk(event)` |
| `promote_chunks/` | Cloud Run **job** `promote-chunks` | Cloud Scheduler → Workflow (daily by default) | `main()` |
| `load_sso/` | Cloud Run function `load-sso` + Dataflow flex template | Eventarc on `load-sso-topic` | `load_sso(event)` |

All use `lsst.dax.ppdb.gcp` for structured logging (`CloudEventLogger`,
`setup_cloud_logging`), Pub/Sub decoding (`decode_message_data`), and Sentry
(`cloud_run_initialize_sentry`, `@flush_sentry`).

## Message contracts

| Topic | Publisher | Payload (JSON) |
|---|---|---|
| `stage-chunk-topic` | dax_ppdb `ChunkUploader` | `{"chunk_id": "<id>", "folder": "gs://<bucket>/<id>"}` |
| `load-sso-topic` | dax_ppdb `SSOUploader` | `{"bucket": ..., "object_prefix": ..., "uploaded_tables": [...]}` |

Changing a payload means changing both the publisher (often in dax_ppdb) and
the consumer here.

## stage_chunk

- `main.py` checks the message (`chunk_id`, `folder`) and calls dax_ppdb
  `ChunkStager.stage_chunk`. The stager loads each Parquet file into a
  per-chunk table in `ppdb_landing` with BigQuery load jobs, then copies them
  into staging in one transaction that checks the row counts against the
  manifest. It sets the chunk to `staging`, then `staged`, `retrying` or
  `failed`.
- Error policy: bad messages, rejected chunks and permanent failures are
  logged and acked. Temporary errors are raised, so Pub/Sub retries (100
  attempts, then `stage-chunk-dlt`).
- Env (from Terraform): `PPDB_CONFIG_URI`, `CLOUDSQL_*`,
  `BIGQUERY_CHECK_TIMEOUT_SECONDS`, `BIGQUERY_JOB_TIMEOUT_SECONDS`,
  `BIGQUERY_RETRY_TIMEOUT_SECONDS`, `LOG_LEVEL`.

## track_chunk

- Builds `PpdbBigQuery.from_env()` at import. Supports only
  `operation == "update"` with `values.status`.
- Error policy: bad message or chunk not found → log and return, so there's no
  retry. `sqlalchemy.exc.OperationalError` → re-raise, so Pub/Sub retries.
  Other SQLAlchemy errors → log, no retry.
- Env (from Terraform): `PPDB_CONFIG_URI`, `PPDB_USE_SECRET_MANAGER`,
  `CLOUDSQL_*`, `PROJECT_ID`, `SENTRY_*`.

## promote_chunks

- `PpdbBigQuery.from_env()` → `get_promotable_chunks()` → `ChunkPromoter.promote_chunks()`.
  `NoPromotableChunksError` is logged as a warning, which is the normal case
  when nothing is staged; other errors fail the job execution.
- Container: `python:3.13-slim` running `python main.py`.
- Promotion logic lives in dax_ppdb. See [dax_ppdb § Promotion](dax_ppdb.md).

## load_sso

- Launches the `load_sso` flex template with `tables`, `staging_dataset_id`,
  `internal_dataset_id`, and `DATAFLOW_MACHINE_TYPE`.
- `load_sso_beam_job.py`: for each table, create an expiring staging table with
  the internal table's schema, load Parquet (`WRITE_TRUNCATE`, NaN/inf →
  NULL), then copy staging → internal with `WRITE_TRUNCATE`. This is a full replace.

## Deployment (GitHub Actions)

| Workflow | Deploys | Triggers |
|---|---|---|
| `stage-chunk-deploy-{dev,int,prod}` | function `stage-chunk` | manual (`workflow_dispatch`), or from `deploy-all-<env>` |
| `track-chunk-deploy-{dev,int,prod}` | function `track-chunk` | same |
| `promote-chunks-deploy-{dev,int,prod}` | image → Artifact Registry `ppdb-repo/promote-chunks:<sha>` → Cloud Run job | same |
| `load-sso-deploy-{dev,int,prod}`, `load-sso-build-flex-deploy-{dev,int,prod}` | load_sso function and template | same |
| `deploy-all-{dev,int,prod}` | every function and job in that environment | manual (`workflow_dispatch`) |

Consequences:

- **Nothing deploys automatically.** Pull requests and pushes to `main`
  deploy nothing; each environment, dev included, is deployed by running a
  workflow by hand.
- Terraform creates each function with placeholder code and
  `ignore_changes` on the source, so code comes only from these workflows.
  Env vars, service accounts, triggers and scaling come only from Terraform.
- Workflow config uses GitHub environment variables and secrets
  (`vars.GCP_DEV_PROJECT_ID`, `secrets.GCP_CREDENTIALS_DEV`, per-function
  CPU/memory/timeout vars). These aren't visible in the repo.

## dax_ppdb pin

Every `requirements*.txt` pins
`lsst-dax-ppdb @ git+https://github.com/lsst/dax_ppdb@cloudrun-vX.Y.Z`
(the latest `cloudrun-v*` tag in dax_ppdb). Released dax_ppdb changes reach
the functions only through these `cloudrun-v*` tags.

Usual workflow for a change that needs unreleased dax_ppdb code:

1. Pin the affected functions to the dax_ppdb ticket branch
   (`@tickets/DM-NNNNN`).
2. If a deploy doesn't pick up new commits on that branch (the Google build
   caches the install), pin to a commit SHA (`@<sha>`) instead.
3. Before merging, tag dax_ppdb `cloudrun-vX.Y.Z` and set the pins to that
   tag. Then merge (dev) or dispatch (int).

## Local

`scripts/setup-dev-env.sh` exports dev settings (`PROJECT_ID=ppdb-dev-5c07`,
`REGION=us-central1`, …). Use the `ppdb_env` conda env.
