# ppdb-cloud-functions reference

`repos/ppdb-cloud-functions`. Written from a code survey at `b4b4ed7` (2026-10-13).
The repo `README.md` is stale; this doc and the workflows are more accurate.

## Units

| Dir | GCP resource (name) | Trigger | Entry point |
|---|---|---|---|
| `stage_chunk/` | Cloud Run function `trigger-stage-chunk` + Dataflow flex template | Eventarc on `stage-chunk-topic` | `trigger_stage_chunk(event)` |
| `track_chunk/` | Cloud Run function `track-chunk` | Eventarc on `track-chunk-topic` | `track_chunk(event)` |
| `promote_chunks/` | Cloud Run **job** `promote-chunks` | Cloud Scheduler → Workflow (daily by default) | `main()` |
| `load_sso/` | Cloud Run function `load-sso` + Dataflow flex template | Eventarc on `load-sso-topic` | `load_sso(event)` |

All use `lsst.dax.ppdb.gcp` for structured logging (`CloudEventLogger`,
`setup_cloud_logging`), Pub/Sub decoding (`decode_message_data`), and Sentry
(`cloud_run_initialize_sentry`, `@flush_sentry`).

## Message contracts

| Topic | Publisher | Payload (JSON) |
|---|---|---|
| `stage-chunk-topic` | dax_ppdb `ChunkUploader` | `{"dataset": "ppdb_staging", "chunk_id": "<id>", "folder": "gs://<bucket>/<prefix>/<id>"}` |
| `track-chunk-topic` | `stage_chunk_beam_job.update_chunk_status` | `{"operation": "update", "apdb_replica_chunk": <id>, "values": {"status": "staged"}}` |
| `load-sso-topic` | dax_ppdb `SSOUploader` | `{"bucket": ..., "object_prefix": ..., "uploaded_tables": [...]}` |

Changing a payload means changing both the publisher (often in dax_ppdb) and
the consumer here.

## stage_chunk

- `main.py` validates the message and launches the flex template
  `DATAFLOW_TEMPLATE_PATH` as job `stage-chunk-<chunk_id>-<UTC timestamp>`. It
  passes `dataset_id`, `chunk_id`, `folder`, `topic_name`, runs as the
  Dataflow service account, and uses `GOOGLE_CLOUD_SUBNETWORK`.
- `stage_chunk_beam_job.py` reads `manifest.json` from the folder, reads each
  Parquet with `ReadFromParquet`, and appends to the staging tables
  (`WRITE_APPEND`). It then publishes `staged` to `track-chunk-topic`.
- Env: `PROJECT_ID`, `DATAFLOW_TEMPLATE_PATH`, `REGION`,
  `SERVICE_ACCOUNT_EMAIL`, `TEMP_LOCATION`, `TOPIC_NAME`, `NUM_RETRIES`,
  optional `GOOGLE_CLOUD_SUBNETWORK`.
- Two dependency files: `requirements.txt` (function) and
  `requirements-dataflow.txt` (Beam container, `Dockerfile`, `metadata.json`).

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
| `stage-chunk-deploy-{dev,int}` | function `trigger-stage-chunk` | dev: PR + push to `main` on path changes; int: manual |
| `dataflow-build-flex-deploy-{dev,int}` | stage_chunk Beam image + flex template | same pattern |
| `track-chunk-deploy-{dev,int}` | function `track-chunk` | same pattern |
| `promote-chunks-deploy-{dev,int}` | image → Artifact Registry `ppdb-repo/promote-chunks:<sha>` → Cloud Run job | same pattern |
| `load-sso-deploy-{dev,int}`, `load-sso-build-flex-deploy-{dev,int}` | load_sso function and template | same pattern |

Consequences:

- **A PR touching a function's files deploys it to dev before review.**
- Int is deployed by hand (`workflow_dispatch`).
- Terraform creates each function with placeholder code and
  `ignore_changes` on the source, so code comes only from these workflows.
  Env vars, service accounts, triggers and scaling come only from Terraform.
- Workflow config uses GitHub environment variables and secrets
  (`vars.GCP_DEV_PROJECT_ID`, `secrets.GCP_CREDENTIALS_DEV`, per-function
  CPU/memory/timeout vars). These aren't visible in the repo.

## dax_ppdb pin

Every `requirements*.txt` pins
`lsst-dax-ppdb @ git+https://github.com/lsst/dax_ppdb@cloudrun-vX.Y.Z`
(currently `cloudrun-v2.2.0`), except `stage_chunk/requirements-dataflow.txt`,
which uses `@main`. To ship a dax_ppdb change, tag dax_ppdb, bump the pins,
and merge (dev) or dispatch (int).

## Local

`scripts/setup-dev-env.sh` exports dev settings (`PROJECT_ID=ppdb-dev-5c07`,
`REGION=us-central1`, …). Use the `ppdb_env` conda env.
