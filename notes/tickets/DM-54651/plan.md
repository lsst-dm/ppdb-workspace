# DM-54651: Improve data integrity checks and state handling in PPDB chunk ingestion

<!-- The plan: goal, approach, scope. Written at the start; Claude asks
     before changing it. Progress goes in todo.md; decisions and findings
     go in notes.md. -->

Jira: https://rubinobs.atlassian.net/browse/DM-54651
Status: in progress

## Goal

Make sure chunks aren't staged more than once, and that a chunk whose
staging fails is logged and set to `failed`. Minimal changes, no refactoring.

## Approach

`stage_chunk`:

1. Accept only `uploaded` or `failed` chunks.
2. Read the manifest, then check the staging tables it lists for the chunk's
   rows.
3. Set the chunk to `staging`.
4. Launch the Dataflow job as `stage-chunk-{chunk_id}` (no timestamp), so a
   duplicate active job is rejected with 409.

Any non-retryable failure, and a retryable launch failure, sets the chunk to
`failed`. The Beam job logs only errors and publishes `failed` when the
pipeline or manifest read fails.

dax_ppdb adds the `staging` status, `handle_database_error` and
`Manifest.from_uri`. The uploader resets a chunk to `exported` and clears its
GCS URI when the staging message can't be published.

idf_deploy gives `stage_chunk` Cloud SQL access, read access to the config
bucket, BigQuery job user, and data viewer on staging.

## Out of scope (follow-up tickets)

Findings for each are in `notes.md`.

### Staging integrity

- Reject invalid status changes for chunks, using a data structure that
  lists the valid transitions.
- Make marking a chunk as in progress atomic (one database operation), so
  two simultaneous requests can't both start staging it.
- After staging, check the number of rows in each staging table against the
  chunk's manifest.
- An incorrect number of rows should likely revert the staged data.

### Failure handling and recovery

- Record the Dataflow job ID in the chunk tracking table (new
  `dataflow_job_id` column).
- Record an error message for failed chunks (new `error_message` column).
- Improve error handling in the chunk uploader:
  - Record failed uploads and the reason for them
  - Limit retries of failed chunks
  - Retry only temporary errors
  - Clean up a chunk's state completely after a failed upload
  - Handle different kinds of errors deliberately, instead of catching
    everything
  - Add tests for the failure cases
- Detect Dataflow job failures that happen outside the pipeline code, and
  staging requests that run out of retries, and mark the chunk `failed`.
- Tooling to relaunch failed chunks, including cleaning up partially staged
  data.

### Other

- Switch to psycopg (v3).
- Crash safety for promotion (DM-56671).

## Repos and branches

| Repo | Branch | PR |
|---|---|---|
| dax_ppdb | tickets/DM-54651-v2 | [#68](https://github.com/lsst/dax_ppdb/pull/68) |
| ppdb-cloud-functions | tickets/DM-54651-v2 | [#35](https://github.com/lsst-dm/ppdb-cloud-functions/pull/35) |
| idf_deploy | tickets/DM-54651-v2 | [#976](https://github.com/lsst/idf_deploy/pull/976) |
| ppdb-workspace | tickets/DM-54651 | [#3](https://github.com/lsst-dm/ppdb-workspace/pull/3) |

## Cross-repo dependencies

- dax_ppdb merge → tag `cloudrun-vX.Y.Z` → set the `lsst-dax-ppdb` pin in
  `stage_chunk` and `track_chunk` to that tag.
- idf_deploy must be applied before the new `stage_chunk` is deployed,
  because the function now connects to Cloud SQL.
- Database grants for `cloudrun-trigger-stage-chunk` are run by hand
  (`services/SQL/iam-sa-permissions.sql`).

## Open questions

1. Does Dataflow return 409 for a duplicate active job name?
2. Does the flex template launcher wait for the Beam job to finish?
