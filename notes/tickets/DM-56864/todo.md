# DM-56864: to-do

<!-- Concrete steps as a checklist. Claude checks items off and adds new
     ones as work proceeds. Keep items small enough to finish in a session. -->

- [x] Create `tickets/DM-56864` in `dax_ppdb` and `ppdb-cloud-functions` (from `main`)
- [x] Create `tickets/DM-56864` in `idf_deploy`
- [x] Start `dax_ppdb` and `ppdb-cloud-functions` branches from `tickets/DM-54651-v2`
- [x] After DM-54651 merges, rebase branches onto `main`
- [x] DM-56849 (push subscriptions) merged before deploying `stage_chunk`
- [x] Resolve open questions in `plan.md`
- [x] Check Parquet column types load into the BigQuery tables without conversion (dev)
- [x] Verify the commit transaction (`ASSERT`/`INSERT … SELECT` across four tables) in dev
- [x] Check current BigQuery quotas against the plan's figures. About 144 chunks a day use roughly 10% of the 1,500 daily writes per table, and quota errors are retried
- [x] Handle 403 `quotaExceeded`/`rateLimitExceeded` as transient in `ChunkStager`
- [x] dax_ppdb: `DatasetType.LANDING`, `Datasets.landing`, `TableRefs.landing(table, chunk_id)`
- [x] dax_ppdb: `status_time`, `error_message` and `staging_job_id` chunk table columns; `update_chunks` sets `status_time`
- [x] Add the new chunk table columns to the dev database
- [x] dax_ppdb: `ChunkStatus.RETRYING` and `bigquery.chunk_stager.ChunkStager`
- [x] dax_ppdb: integration test for `ChunkStager`
- [x] ppdb-cloud-functions: `stage_chunk` calls `ChunkStager`
- [x] Remove `track_chunk` (ppdb-cloud-functions and idf_deploy)
- [x] Revoke the `cloudrun-track-chunks` Postgres grants in dev
- [x] ppdb-cloud-functions: remove the Beam job, Dockerfile, flex template and build workflows
- [x] idf_deploy: `ppdb_landing` dataset (default table expiration) and stage chunk service account IAM
- [x] idf_deploy: remove stage chunk Dataflow service account, IAM and variables
- [x] idf_deploy: keep one `stage-chunk` instance running (`min_instance_count = 1`)
- [x] Set the stage chunk function's memory variable to 1Gi in the int and prod GitHub environments (512Mi ran out of memory in dev)

Review findings (dax_ppdb):

- [x] Check the staging tables for the chunk's rows before loading; fail the chunk with the row counts if any exist
- [x] Set a 4-minute `job_timeout_ms` on the load jobs and the transaction, settable through the function's environment from Terraform
- [x] Store `error_message` with `retrying` as well as `failed`
- [x] Uploader: drop the unused `dataset` field from the stage chunk message
- [x] Replace the `ppdb-{env}-ingest` bucket with `ppdb-{env}-chunk-ingest`, remove the old bucket, and update everything that refers to it
- [x] dax_ppdb: add `geo_point` to the staging DIA tables, set it to `ST_GEOGPOINT(ra, dec)` when staging, and copy it through on promotion

dax_ppdb, `ChunkStager`:
- [x] Make the already-staged check (`_check_not_already_staged`) clearer
- [x] Revisit overwriting the landing tables of an earlier attempt; the docstring is unclear and the behaviour may not be wanted
- [x] Log at debug level when the landing load jobs have finished
- [x] Shorten the `ASSERT` note in the `_copy_to_staging` docstring
- [x] Check that the dax_ppdb documentation covers the new modules (e.g. `chunk_stager`), and add any that are missing
- [x] Go through `chunk_stager.py` and keep inline comments to short notes on what a block does; move technical explanations into the method or class docstring notes

dax_ppdb, status tracking:
- [x] Remove `ChunkTracker` and track chunk status with the existing `PpdbBigQuery` methods (`find_chunk_by_id`, `update_chunks`)
- [x] Remove `PpdbBigQuery.update_chunk_status`
- [x] Replace `ChunkStatus.allowed_from`, `can_transition_to` and the transition map with direct checks of the allowed statuses where they're needed (staging and promotion); a transition map can come later
- [x] Remove `tests/test_chunk_tracker.py`

dax_ppdb, datasets:
- [x] Don't create the landing dataset in the dataset builder, since it has no tables; define it only in Terraform, and adjust the tests

idf_deploy:
- [x] Write a description for lsst/idf_deploy#981

Scope:
- [x] Expand the ticket to cover a broader overhaul of the ingest configuration and organization

Reviewer:
- [x] Pass `job_retry=None` to the stager's BigQuery queries, so the client doesn't resubmit failed jobs under new IDs and Pub/Sub does the retrying
- [x] Treat `google.api_core.exceptions.RetryError` as a temporary error in `ChunkStager`
- [x] Store `e.message` instead of `str(e)` for Google Cloud errors in the retrying branch
- [x] Fix the `stage_chunk` function docstring: database and unexpected errors are retried too, not only transient staging errors
- [x] idf_deploy: give the stage chunk service account `storage.objectViewer` on the chunk ingest bucket instead of project-wide `storage.admin`, and drop its topic subscriber role

Deployment to dev and int:

Merging lsst/idf_deploy#981 applies the services Terraform to dev, int and
prod at once, so the steps before the apply are done in both dev and int
first. Uploads stay paused until the real `stage-chunk` code is deployed,
because until then the placeholder function drops messages.

Before the Terraform apply:
- [ ] Merge lsst/dax_ppdb#69 and release it
- [ ] Add the chunk table columns (`status_time`, `error_message`, `staging_job_id`) in int (dev done)
- [ ] Pause chunk uploads (USDF `ppdb-replication`), and let the `trigger-stage-chunk` subscription and the last Dataflow staging jobs finish, in dev and int
- [ ] Revoke the Postgres grants of `cloudrun-trigger-stage-chunk` (dev and int) and `cloudrun-track-chunks` (int, dev done), so their Cloud SQL users can be dropped
- [ ] Empty `ppdb-dev-ingest` and `ppdb-int-ingest` (Terraform can't delete a bucket that has objects)
- [x] Copy the repository variables `TRIGGER_STAGE_CHUNK_{CPU,MEMORY,TIMEOUT}` to `STAGE_CHUNK_*` in ppdb-cloud-functions (they are repository-level, shared by dev, int and prod)
- [ ] Set `STAGE_CHUNK_TIMEOUT` to 1800 (30 minutes), to allow for the BigQuery retries

Terraform apply:
- [ ] Merge lsst/idf_deploy#981, and check that the dev and int services applies succeed and whether the prod run fails (prod has no project yet)

After the apply:
- [ ] Create the BigQuery tables with the new staging schema (`geo_point`, clustered by `apdb_replica_chunk`): in dev, where the datasets are recreated empty, and in int
- [ ] Grant `cloudrun-stage-chunk` its `chunk_tracking` permissions (`SQL/iam-sa-permissions.sql`) in dev and int
- [ ] Upload the PPDB configs with `bucket_name: ppdb-{env}-chunk-ingest` to `gs://ppdb-dev-config` and `gs://ppdb-int-config`
- [ ] Replace the "DO NOT MERGE" dax_ppdb pins (`stage_chunk` and `promote_chunks`) in lsst-dm/ppdb-cloud-functions#38 with the release, and merge it
- [ ] Deploy `stage-chunk` and `promote-chunks` by hand to dev, then int (`stage-chunk-deploy-<env>`, `promote-chunks-deploy-<env>`)
- [ ] Update USDF `ppdb-replication` (phalanx) to the dax_ppdb release and the new configs, and resume uploads
- [ ] Check that a chunk goes through `uploaded` → `staged` → `promoted` in dev, then in int

Cleanup after merge:
- [ ] Delete the Dataflow staging leftovers in dev and int: `stage_chunk_flex_template.json` in `ppdb-<env>-dataflow`, and the `stage-chunk-image` image in `ppdb-repo`
- [ ] In ppdb-cloud-functions, delete the `*/stage-chunk-dataflow` GitHub environments and, once dev and int are migrated, the `TRIGGER_STAGE_CHUNK_*` and `TRACK_CHUNK_*` repository variables
- [ ] Update `docs/` for the removal of `track_chunk` and the Dataflow stage chunk job

Reviewer (`chunk_stager.py`, second review):
- [x] Cancel the staging transaction (`job.cancel()`) before raising a retryable error once it has been submitted, so a retry can't overlap a transaction that is still running and stage the chunk twice
- [x] Narrow or drop the `_copy_to_staging` Notes sentence saying the `ASSERT` catches rows committed after the already-staged check (under snapshot isolation it only sees rows committed before the transaction starts)
- [x] Check in dev which errors the Cloud SQL connector raises (e.g. token refresh failures) and whether they are `SQLAlchemyError`; if not, add them to the database `except` clauses
- [x] Check in dev which error a BigQuery job stopped by `job_timeout_ms` raises, and a transaction aborted by a concurrent update; retry them if appropriate. Decided: both are treated as fatal for now (no change)
- [x] Pass a client-side `timeout` to `job.result()`, and describe the Pub/Sub deadline budget as approximate (it leaves out `get_table`, Postgres and polling). Not needed: BigQuery's job limits bound each wait, and the deadline wording is gone
- [x] Raise `InvalidManifestError` for a manifest with no files, instead of running an empty query. Not needed: empty chunks are never staged
- [x] Comment that `ServerError` includes 501, which is permanent. Not needed: BigQuery doesn't return 501 for the stager's calls
- [x] Reword "errors of types known to be temporary" in the `stage_chunk` Notes, e.g. "temporary errors (429, 5xx, network)"
- [x] Shorten the inner `try` comment in `stage_chunk` to "Copy the chunk into staging."
- [x] Shorten the `_copy_to_landing` summary line and move the `geo_point` detail to its Notes
