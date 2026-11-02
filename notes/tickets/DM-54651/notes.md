# DM-54651: Notes

<!-- Reference notes, organized by topic and edited in place. Keep
     decisions and why, findings, gotchas and open questions. Not a work
     log: no session entries, progress updates or commit hashes. -->

## Decisions

- Minimal changes, no refactoring. An earlier approach (a `ChunkStager` class
  in dax_ppdb and enforced status changes) was abandoned as too much
  refactoring. Its branches remain for reference: dax_ppdb #62 and
  ppdb-cloud-functions #29 (`tickets/DM-54651`), and the local
  `tickets/DM-54651-stager` and `tickets/DM-54651-old`.
- The logic stays in the Cloud Run functions for now, not in dax_ppdb.
- `staging` is set after the checks, before the launch, with the existing
  `update_chunks`. It isn't atomic.
- `handle_request_error` was renamed `handle_dataflow_launch_error`, since it
  is used only for Dataflow launches. Manifest and BigQuery errors are
  classified where they're caught.
- The uploader resets a chunk to `exported` (and clears its GCS URI) when the
  staging message can't be published, rather than marking it `failed`.
- Retry policy in `stage_chunk`: 429, all 5xx and network errors (including
  `requests` and credential transport errors) are retried. Other 4xx and
  unexpected errors are permanent and mark the chunk `failed`.
- `Manifest.from_uri` wraps only parse errors (all `ValueError` subclasses)
  in `InvalidManifestError`. Read errors propagate unwrapped so the caller
  can tell transient from permanent; no `ManifestReadError` class.
- `stage_chunk` opens one `PpdbBigQuery` per request and passes it to
  `_mark_chunk_failed`, instead of opening one per status update.

## Known gaps

- A pipeline can fail after some tables are loaded. The row check then blocks
  a relaunch until the rows are cleaned up by hand.
- If Dataflow fails outside our code, nothing reports it, so the chunk stays
  `staging`. Proposed fix: an Eventarc trigger on Dataflow job status.
- Retryable `stage_chunk` errors are retried, then dropped. `stage-chunk-dlt`
  exists but isn't wired to the trigger.
- The Beam job's `staged` and `failed` messages depend on the flex template
  launcher waiting for it (open question in `plan.md`).
- If the Beam job loads the data but can't publish `staged` (or can't publish
  `failed` after an error), the chunk stays `staging`. Needs detection from
  outside the job (follow-on).
- After a retried launch, the row check can log `chunk_already_staged` at
  error level while the first job is still running. Harmless; the job later
  publishes `staged`.
- A chunk is `uploaded` with staging rows only if left over from the old
  `stage_chunk` or changed by hand. It's skipped without being marked
  `failed`.
- Eventarc's fixed 10 second ack deadline is shorter than a cold start, so
  Pub/Sub redelivers and the status check logs `invalid_chunk_status`
  warnings for the duplicates. Fix in DM-56849.

## Gotchas

- `lsst.resources` gs paths retry 429 and 5xx themselves. A missing object
  raises `FileNotFoundError`.
- Beam writes use file loads (batch), so there's no streaming buffer and a
  DML `DELETE` works right away. Writes aren't atomic across tables.

## Follow-on tickets

Scope is in `plan.md`. These are findings for whoever picks them up.

### Staging integrity (from the abandoned branch)

- Enforcing status changes rejects `uploaded → staged`, so every `staged`
  message fails until `stage_chunk` sets `staging` first. The dax_ppdb
  release, `stage_chunk` and `track_chunk` must deploy together.
- Chunks with a job running at deploy time can get stuck. Deploy at a quiet
  moment, or handle those chunks.
- A duplicate `staged` message would raise a status-change error in
  `track_chunk`. Treat it as already done, not as an error.

### Failure handling and recovery: relaunch

- Proposed: claim a `failed` chunk, then delete its staging rows before
  relaunching. For an `uploaded` chunk, any rows mean something went wrong,
  so reject it.
- `ChunkPromoter._delete_staged_chunks()` already deletes staging rows by
  chunk ID and can be reused.
- The manifest has a per-table `row_count` for checking rows after staging.

### BigQuery load jobs (DM-56864)

- Dataflow does no transformation for staging; batch `WriteToBigQuery` runs
  load jobs itself. Load jobs would put the staging code in dax_ppdb and let
  `stage_chunk` set `staged` or `failed` directly.
- DM-56849 is a prerequisite: a synchronous `stage_chunk` would always exceed
  the Eventarc ack deadline.
- `load_sso` would move to load jobs on a separate ticket.

### Switch to psycopg (v3)

- SQLAlchemy 2.1 uses psycopg (v3) for `postgresql://` by default, and
  dax_ppdb lists only `psycopg2-binary`. dax_ppdb pins `sqlalchemy<2.1` for
  now.
- With psycopg (v3), the dax_apdb Postgres tests fail in
  `ApdbSql._storeDiaObjects`: an all-`None` `validityEndMjdTai` column is
  bound as `NULL::VARCHAR`. That blocks the switch.
