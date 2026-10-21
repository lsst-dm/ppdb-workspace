# DM-54651: TODO

<!-- Concrete steps as a checklist. Claude checks items off and adds new
     ones as work proceeds. Keep items small enough to finish in a session. -->

## Code

- [x] Fixed Dataflow job name `stage-chunk-{chunk_id}`
- [x] `stage_chunk` accepts only `uploaded` or `failed` chunks
- [x] `stage_chunk` checks the staging tables for the chunk's rows
- [x] `staging` status set before launch
- [x] Chunk marked `failed` when staging fails (`stage_chunk` and the Beam job)
- [x] Beam job logs only errors, structured
- [x] Uploader resets the chunk to `exported` and clears its GCS URI when the
  staging publish fails
- [x] `Manifest.from_uri`; manifest read in its own step in `stage_chunk`
- [x] idf_deploy: Cloud SQL and BigQuery access for `stage_chunk`
