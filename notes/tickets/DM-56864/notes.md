# DM-56864: notes

<!-- Dated log, newest last. Claude appends at the end of each session or
     major step: what was done, findings, decisions and why, commands that
     worked, dead ends, what's blocked. -->

## 2026-10-29

- `ppdb_promotion` is created by the dataset builder. The other PPDB datasets
  are in `idf_deploy` `services/bigquery.tf`.
- Ticket branches in `dax_ppdb` and `ppdb-cloud-functions` fast-forwarded to
  `tickets/DM-54651-v2`. Ignore the local `tickets/DM-54651-stager` branches.

## 2026-11-03

- `ChunkTracker`, reclaiming and the transition map are gone. `ChunkStager`
  checks the status in Python and writes with `PpdbBigQuery.update_chunks`. A
  duplicate message racing the status check is accepted for now.
- `VERSION` stays 0.1.0: how it interacts with the APDB is unclear.
- Building the staging tables with `StagingDatasetBuilder` in the integration
  test is in `notes/backlog.md`: the test schema's DiaObject already has
  `validityEndMjdTai`, which the builder adds too.
- Stage chunk service account: `storage.objectViewer` on the chunk ingest
  bucket replaces project-wide `storage.admin`.
- `docs/` (architecture, ppdb-cloud-functions) still describes `track_chunk`
  and the Dataflow stage chunk job.
- Deployment checklist for dev and int is in `todo.md` ("Deployment to dev
  and int"). Merging lsst/idf_deploy#981 applies the services Terraform to
  dev, int and prod at once, so the pre-apply steps are done in both envs
  first. Until the real `stage-chunk` code is deployed after the apply, the
  placeholder function acks and drops messages, so uploads stay paused. Prod
  has no project yet, so its services run may fail on merge.
- `with_updates` replaced by typed `with_new_error_message` and
  `with_new_staging_job_id`. A typed `with_updates` (`TypedDict` + `Unpack`)
  replacing all the `with_new_*` methods is left for a later refactor.

## 2026-11-04

- BigQuery API requests in `ChunkStager` are retried for up to
  `BIGQUERY_RETRY_TIMEOUT_SECONDS` (300). The client's default was 600.
  `STAGE_CHUNK_TIMEOUT` should be about 30 minutes to cover the job limits
  plus retries.
- If waiting for the staging transaction fails, the job is cancelled and the
  chunk set to `failed` instead of `retrying`, so a retry can't overlap the
  running transaction and stage the chunk twice. The job may still have
  committed.
- Cloud SQL connector errors (`google.auth`, `aiohttp`, `OSError`) are not
  wrapped as `SQLAlchemyError` by SQLAlchemy 2.0. `DATABASE_ERRORS` covers
  them, and `handle_database_error` classifies them.
- BigQuery quota errors are 403 with the reason (`quotaExceeded`,
  `rateLimitExceeded`) in `e.errors`, not `e.reason`. They now set `retrying`.
- The stage chunk subscription allows 100 delivery attempts (about 16 hours).
  Pub/Sub's maximum is 100.
- A BigQuery job stopped by its time limit, and a transaction aborted by a
  concurrent update, are treated as fatal for now.
- `handle_dataflow_launch_error` is still used by `load_sso`, so it stays.
- ppdb-cloud-functions deploys only by hand (`workflow_dispatch`), in every
  environment.

## Revoking the old service accounts' Postgres grants

Before the Terraform apply drops their Cloud SQL users, revoke what
`SQL/iam-sa-permissions.sql` granted. Run in the `ppdb` database as the admin
user that ran the original grants.

Dev:

```sql
REVOKE SELECT, UPDATE ON ALL TABLES IN SCHEMA chunk_tracking FROM "cloudrun-trigger-stage-chunk@ppdb-dev-5c07.iam";
REVOKE USAGE ON SCHEMA chunk_tracking FROM "cloudrun-trigger-stage-chunk@ppdb-dev-5c07.iam";

-- The table and schema grants of cloudrun-track-chunks were already revoked,
-- but not its default privileges, so Terraform couldn't drop the user
-- ("some objects depend on it").
ALTER DEFAULT PRIVILEGES IN SCHEMA chunk_tracking
REVOKE SELECT, INSERT ON TABLES FROM "cloudrun-track-chunks@ppdb-dev-5c07.iam";

SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'cloudrun-trigger-stage-chunk@ppdb-dev-5c07.iam';
```

Int:

```sql
REVOKE SELECT, UPDATE ON ALL TABLES IN SCHEMA chunk_tracking FROM "cloudrun-trigger-stage-chunk@ppdb-int-6c62.iam";
REVOKE USAGE ON SCHEMA chunk_tracking FROM "cloudrun-trigger-stage-chunk@ppdb-int-6c62.iam";

ALTER DEFAULT PRIVILEGES IN SCHEMA chunk_tracking
REVOKE SELECT, INSERT ON TABLES FROM "cloudrun-track-chunks@ppdb-int-6c62.iam";
REVOKE SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA chunk_tracking FROM "cloudrun-track-chunks@ppdb-int-6c62.iam";
REVOKE USAGE ON SCHEMA chunk_tracking FROM "cloudrun-track-chunks@ppdb-int-6c62.iam";

SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('cloudrun-trigger-stage-chunk@ppdb-int-6c62.iam', 'cloudrun-track-chunks@ppdb-int-6c62.iam');

SELECT pg_get_userbyid(defaclrole) AS granted_by, defaclacl
FROM pg_default_acl
WHERE defaclacl::text LIKE '%cloudrun-track-chunks%';
```

The `SELECT` queries should return no rows. `ALTER DEFAULT PRIVILEGES …
REVOKE` only affects the role that runs it, so if the last query still shows a
row, rerun it with `FOR ROLE <granted_by>`.

## Testing the error paths

Only the happy path is tested so far: `test_chunk_stager.py` has one staging
test and a pickle test, and ppdb-cloud-functions has no tests. Options, most
useful first:

- **Mock unit tests for `ChunkStager`.** Replace the BigQuery client and the
  `PpdbBigQuery` database calls with mocks that raise chosen errors, then check
  the raised exception and the recorded status and error message. They need no
  GCP access and cover the errors that are hard to cause for real:
  - 5xx, 429, network errors and `RetryError` give `retrying` and
    `ChunkStagingRetryableError`
  - 403 `quotaExceeded` or `rateLimitExceeded` gives `retrying`
  - 400 and other permanent errors give `failed` and `ChunkStagingError`
  - a lost staging transaction calls `job.cancel()` and fails the chunk with
    "Could not get the result…"
  - a database error before staging goes through `handle_database_error`
  - a database error while writing the failure status raises
    `ChunkStagingError`, and the chunk stays in `staging`
  - a failed landing table drop only logs a warning
- **Real failures in the dev integration test**, next to the staging test:
  - wrong chunk status raises `ChunkStatusError`
  - rows already in staging fail the chunk with the row counts
  - a wrong manifest row count fails the `ASSERT`, and no rows are left behind
  - a missing or broken Parquet file fails the load job
- **`stage_chunk` function test.** Call the handler with a fake Pub/Sub event
  and a mocked `ChunkStager`. Check that a retryable error makes Pub/Sub
  redeliver and a fatal error acknowledges the message. It can also run
  locally with `functions-framework`.
- **By hand in dev.** Publish messages to `stage-chunk` for a bad chunk ID or a
  corrupt file, and watch the chunk status, the logs and the dead-letter topic.
  This is the only way to test the real Pub/Sub retry and dead-letter settings.

### Manual tests in dev (2026-11-06)

The messages were published to `stage-chunk-topic`, with the expected result
of each in a comment:

```bash
# Check the active project, which must be ppdb-dev-5c07.
gcloud config get-value project

# Publish one message to the stage chunk topic and print its message ID.
pub() {
  gcloud pubsub topics publish stage-chunk-topic --project ppdb-dev-5c07 \
    --message="$1" --format='value(messageIds)'
}

pub '{"chunk_id": 1609459200, "folder": "gs://ppdb-dev-chunk-ingest/1609459200"}'  # chunk_rejected (promoted)
pub '{"chunk_id": 999, "folder": "gs://ppdb-dev-chunk-ingest/999"}'                # chunk_not_found
pub 'not json'                                                                     # json_decode_error
pub '{}'                                                                           # invalid_chunk_id (KeyError)
pub '{"chunk_id": "abc", "folder": "gs://x"}'                                      # invalid_chunk_id (ValueError)
pub '{"chunk_id": null, "folder": "gs://x"}'                                       # invalid_chunk_id (TypeError)
pub '[1, 2]'                                                                       # invalid_payload_type
pub '{"chunk_id": 999}'                                                            # missing_folder
```

The chunk statuses were checked afterwards, with the Cloud SQL proxy running
on port 5432 (see `docs/chunk-tracking-db.md`):

```bash
psql "host=127.0.0.1 port=5432 user=jeremym@lsst.cloud dbname=ppdb sslmode=disable options='-c role=ppdb'" \
  -c 'select apdb_replica_chunk, status, status_time, error_message
      from chunk_tracking."PpdbReplicaChunk" where apdb_replica_chunk in (1609459200, 999)'
```

Each message ran once and returned HTTP 200, so it was acked and not
redelivered. Chunk `1609459200` stayed `promoted` with its old `status_time`,
and no row was created for `999`.

| Message | Log event | Severity |
|---|---|---|
| `{"chunk_id": 1609459200, "folder": …}` (promoted chunk) | `chunk_rejected`, status `promoted` | WARNING |
| `{"chunk_id": 999, "folder": …}` (unknown chunk) | `chunk_not_found` | WARNING |
| `not json` | `json_decode_error` | ERROR |
| `{}` | `invalid_chunk_id` (`KeyError`) | ERROR |
| `{"chunk_id": "abc", "folder": "gs://x"}` | `invalid_chunk_id` (`ValueError`) | ERROR |
| `{"chunk_id": null, "folder": "gs://x"}` | `invalid_chunk_id` (`TypeError`) | ERROR |
| `[1, 2]` | `invalid_payload_type` | ERROR |
| `{"chunk_id": 999}` (no folder) | `missing_folder` | ERROR |

Not tested yet:

- An existing chunk with a missing folder, or with another chunk's manifest.
  This needs a chunk in `uploaded` status, and the chunk should end up
  `failed` with the error message.
- Message data that isn't base64 or UTF-8. `gcloud` always sends valid UTF-8,
  so this needs a small Python publisher.
