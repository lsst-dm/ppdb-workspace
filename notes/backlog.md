# Backlog

<!-- Follow-up work that isn't part of a current ticket. Turn an item into a
     Jira ticket when it's picked up, and remove it from here. -->

- A check or tool for a chunk failed with "may already have committed": look up its recorded staging job ID and the staging tables to tell whether its rows reached staging, then set it to `staged` or reset it. Happens when the stager can't get the result of the staging transaction. From DM-56864.
- `ChunkStager` integration test: create the staging tables with `StagingDatasetBuilder` instead of from the Parquet schemas, so staging is tested against the real table definitions. The test schema's DiaObject has `validityEndMjdTai`, which the builder also adds, so the test has to remove it first. From DM-56864.
- `ppdb-cli create-bq` (and `make_database`): without `--db-drop`, SQLAlchemy's `create_all` skips tables that already exist without saying so, so a stale chunk table (e.g. with an old column) looks like a successful run. Log a warning naming the existing tables, or fail unless `--db-drop` or a new `--exists-ok` flag is given. Found in DM-56864.
- dax_ppdb tests leak BigQuery datasets in dev when a run is stopped partway through a test, before its cleanup runs. In CI this happens when one Python version's job fails and the matrix's default fail-fast cancels the other one. Set `fail-fast: false` in `build.yaml`, and delete leftover `test_<name>_*` datasets older than a few hours at the start of the tests, which also covers cancelled and interrupted local runs. Found with `test_chunk_stager` in DM-56864.
