# DM-56864: Replace the stage chunk Dataflow job with BigQuery load jobs

<!-- The plan: goal, approach, scope. Written at the start; Claude asks
     before changing it. Day-to-day progress goes in todo.md and notes.md. -->

Jira: https://rubinobs.atlassian.net/browse/DM-56864
Status: in progress

## Goal

`stage_chunk` stages chunks with BigQuery load jobs through a new
`ChunkStager` in `dax_ppdb`, replacing the Dataflow job and its image,
workflows, service account and IAM. Staging gets all of a chunk or none of it,
never duplicates, and exactly what the manifest says. The ticket also covers
the related ingest cleanup: removing `track_chunk`, the chunk ingest bucket,
dropping `object_prefix`, setting `geo_point` in staging and renaming
`trigger_stage_chunk` to `stage_chunk`.

## Approach

### Data path

```
GCS chunk folder ──load jobs──▶ ppdb_landing.<table>_chunk_<id> ──transaction──▶ ppdb_staging.<table>
```

- Each chunk loads into its own landing tables (e.g.
  `ppdb_landing.DiaObject_chunk_42`), created by the load job with the staging
  table's schema minus `geo_point`.
- Load jobs can't run in a transaction, so one DML transaction then copies all
  of the chunk's tables into staging, setting `geo_point`.
- `ppdb_landing` is created by Terraform. Its tables expire after 1 day by
  default.
- Differs from Jira ("load jobs into the staging tables") to get the
  all-or-nothing commit.

### Chunk states

New status `retrying`. Every status change sets `status_time`.

| Status | Meaning | `error_message` |
|---|---|---|
| `uploaded` | Ready to stage | NULL |
| `staging` | Run in flight | NULL |
| `retrying` | Temporary error, waiting for Pub/Sub retry | set |
| `staged` | Ready for promotion | NULL |
| `failed` | Permanent error, needs a person | set |

```
uploaded / retrying ──▶ staging ──▶ staged
                                 ├─▶ retrying   (temporary: re-raise)
                                 └─▶ failed     (permanent: error_message, ack)
```

- `stage_chunk` stages only `uploaded` or `retrying` chunks and rejects all
  others, including `staging`. A redelivered message that arrives while an
  attempt is running is therefore rejected. The check is in Python and the
  write uses `PpdbBigQuery.update_chunks`, so two duplicate messages arriving
  together can both pass. That is accepted for now.
- A crash or failed status write leaves the chunk in `staging`. There is no
  automatic recovery.

### `ChunkStager.stage_chunk(logger, chunk_id, folder)`

Created once per function instance with the PPDB, a BigQuery client, the job
time limits and the retry timeout.

1. Check the chunk exists (else `ChunkStagingError`) and is `uploaded` or
   `retrying` (else `ChunkStatusError`). Set it to `staging`.
2. Read the manifest and check its chunk ID.
3. Check the staging tables have no rows for the chunk (`_check_not_already_staged`).
4. Load each file into `ppdb_landing.<table>_chunk_<id>` (`CREATE_IF_NEEDED`,
   `WRITE_TRUNCATE`). A retry overwrites an earlier attempt's landing tables.
5. Copy in one transaction, per table: `INSERT … SELECT` with
   `geo_point = ST_GEOGPOINT(ra, dec)`, then `ASSERT` that the chunk's row count
   matches the manifest. Record the job ID in `staging_job_id`.
6. Set the chunk to `staged`.

Each BigQuery API request is retried for up to the retry timeout (5 minutes).
Failed jobs are never resubmitted (`job_retry=None`), so Pub/Sub does the
retrying.

### Failure handling

No raw errors leave `stage_chunk`. The function re-raises
`ChunkStagingRetryableError` for a Pub/Sub retry and acks everything else.

- **Before `staging`:** a database error leaves the status unchanged.
  `handle_database_error` decides whether it is retryable.
- **Temporary** (429, 5xx, network errors, BigQuery `quotaExceeded` and
  `rateLimitExceeded`): set `retrying` with `error_message` and raise
  `ChunkStagingRetryableError`. Backoff caps at 10 minutes, with 100 attempts
  (about 16 hours) before the dead-letter topic, so a chunk can wait out a
  quota.
- **Permanent** (any other error, e.g. a bad manifest, rows already in staging,
  a failed `ASSERT`, a job that hits its time limit): set `failed` with
  `error_message` and raise `ChunkStagingError`.
- **Lost staging transaction:** if waiting for the transaction fails with a
  temporary error, the job is cancelled and the chunk set to `failed`, so a
  retry can't stage it twice. The job may still have committed, and the error
  message says so.
- **Final status write fails:** `ChunkStagingError`, and the chunk is left in
  `staging`.
- `DATABASE_ERRORS` includes the Cloud SQL connector errors that SQLAlchemy
  doesn't wrap.
- The stager never deletes from staging.
- The function's request timeout (`STAGE_CHUNK_TIMEOUT`) is 30 minutes, to
  allow for the job limits plus retries.

### Notes

- Order doesn't matter: promotion only takes a contiguous run of `staged`
  chunks, so chunks can be staged in parallel.
- Schema changes are expected to be additive: add nullable columns to staging,
  internal and public first, then roll out the writer. `ALLOW_FIELD_ADDITION`
  stays off.

## Changes by repo

**dax_ppdb**
- Config: `DatasetType.LANDING`, `Datasets.landing = "ppdb_landing"` and
  `TableRefs.landing(table, chunk_id)`. `object_prefix` removed.
- Chunk model: `ChunkStatus.RETRYING`, `ChunkStatusError`,
  `with_new_error_message` and `with_new_staging_job_id`. New `status_time`,
  `error_message` and `staging_job_id` fields and columns. `update_chunks`
  sets `status_time`.
- New `bigquery/chunk_stager.py`.
- `gcp/error_handling.py`: `DATABASE_ERRORS`, and `handle_database_error`
  classifies Cloud SQL connector errors. `aiohttp` is a listed dependency.
- Staging DIA tables get `geo_point` and are clustered by
  `apdb_replica_chunk`. The promoter copies `geo_point` from staging.
- Integration test for `ChunkStager` in dev.
- Existing databases: `ALTER TABLE "PpdbReplicaChunk" ADD COLUMN status_time
  TIMESTAMPTZ, ADD COLUMN error_message TEXT, ADD COLUMN staging_job_id TEXT`.

**ppdb-cloud-functions**
- `stage_chunk` (renamed from `trigger_stage_chunk`) calls `ChunkStager`.
  Dataflow client and env vars dropped.
- Remove `track_chunk`, the Beam job, Dockerfile, flex template and Dataflow
  build workflows.
- Bump `dax_ppdb` pin.

**idf_deploy** (`environment/deployments/ppdb/services/`)
- `bigquery.tf`: `ppdb_landing` dataset with default table expiration.
- `stage-chunk.tf` (renamed from `trigger-stage-chunk.tf`):
  - `bigquery.jobUser`, `dataEditor` on `ppdb_landing` and `ppdb_staging`, and
    `storage.objectViewer` on the chunk ingest bucket
  - BigQuery check, job and retry limits as env vars
  - one minimum instance, and 100 delivery attempts on its subscription
  - Dataflow roles and env vars removed
- `variables.tf`: Pub/Sub delivery attempts set per subscription.
- `gcs.tf`: `ppdb-<env>-chunk-ingest` replaces `ppdb-<env>-ingest`.
- Remove `dataflow-stage-chunk.tf`, `track-chunk.tf` and their variables.

## Repos and branches

| Repo | Branch | PR |
|---|---|---|
| dax_ppdb | tickets/DM-56864 | lsst/dax_ppdb#69 |
| ppdb-cloud-functions | tickets/DM-56864 | lsst-dm/ppdb-cloud-functions#38 |
| idf_deploy | tickets/DM-56864 | lsst/idf_deploy#981 |

## Cross-repo dependencies

- DM-56849 (push subscriptions) and DM-54651 merged first.
- `dax_ppdb` release → pin bump in `ppdb-cloud-functions`.
- New chunk table columns and staging `geo_point` added in each environment
  before deploying.
- Operational steps before and after the Terraform apply are in `todo.md`.

## Out of scope

- Recovering chunks stuck in `staging`, and checking whether a chunk failed
  with "may already have committed" reached staging (`notes/backlog.md`).
- Refactoring `PpdbBigQuery` and status management (DM-56938).
- `load_sso` port (separate ticket). It must handle the
  `.mask`/`__index_level_*` columns and NaN/Inf that its Beam job cleans up.
