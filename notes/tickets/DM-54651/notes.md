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
- `handle_request_error` is used only for the Dataflow launch. Manifest and
  BigQuery errors are classified where they're caught.
- The uploader resets a chunk to `exported` (and clears its GCS URI) when the
  staging message can't be published, rather than marking it `failed`.

## Known gaps

- A pipeline can fail after some tables are loaded. The row check then blocks
  a relaunch until the rows are cleaned up by hand.
- If Dataflow fails outside our code, nothing reports it, so the chunk stays
  `staging`. Proposed fix: an Eventarc trigger on Dataflow job status.
- Retryable `stage_chunk` errors are retried, then dropped. `stage-chunk-dlt`
  exists but isn't wired to the trigger.
- The Beam job's `staged` and `failed` messages depend on the flex template
  launcher waiting for it (open question in `plan.md`).

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

### Switch to psycopg (v3)

- SQLAlchemy 2.1 uses psycopg (v3) for `postgresql://` by default, and
  dax_ppdb lists only `psycopg2-binary`. dax_ppdb pins `sqlalchemy<2.1` for
  now.
- With psycopg (v3), the dax_apdb Postgres tests fail in
  `ApdbSql._storeDiaObjects`: an all-`None` `validityEndMjdTai` column is
  bound as `NULL::VARCHAR`. That blocks the switch.
