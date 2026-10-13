# dax_ppdb reference

Package `lsst.dax.ppdb` (`repos/dax_ppdb/python/lsst/dax/ppdb/`). Written from
a code survey at `369b67a` (2026-10-13).

## Two backends

`PpdbConfig.from_uri()` reads YAML and dispatches on `implementation_type`
(`_factory.py`):

| `implementation_type` | Config | Implementation | Status |
|---|---|---|---|
| `sql` | `sql.PpdbSqlConfig` | `sql.PpdbSql`: writes APDB rows directly into Postgres tables | Original backend |
| `bigquery` | `bigquery.PpdbBigQueryConfig` | `bigquery.PpdbBigQuery`: exports chunks to Parquet; Postgres holds only the chunk-tracking table | Current focus |

Both implement `Ppdb` (`ppdb.py`): `get_replica_chunks()` and `store(...)`.
`Replicator` (`replicator.py`) drives `store()` from the APDB.

## PpdbBigQueryConfig (`bigquery/ppdb_bigquery_config.py`)

| Field | Default | Notes |
|---|---|---|
| `project_id` | required | GCP project, e.g. `ppdb-dev-5c07`, `ppdb-int-6c62` |
| `bucket_name` | required | Upload bucket, `ppdb-<env>-ingest` |
| `object_prefix` | required | GCS prefix; chunk N goes to `<object_prefix>/<N>/` (`chunks` in dev/int) |
| `replication_dir` | required | Local export dir at USDF; chunk N in `<replication_dir>/<N>/` |
| `sql` | required | `PpdbSqlBaseConfig` (`db_url`, `schema_name`, …) for the chunk-tracking DB |
| `stage_chunk_topic` | `stage-chunk-topic` | Pub/Sub topic published after upload |
| `felis_schema_uri` | `resource://lsst.sdm.schemas/ppdb.yaml` | Schema source for BigQuery tables |
| `datasets` | see below | BigQuery dataset names |
| `parq_batch_size` / `parq_compression` | `10000` / `snappy` | Parquet writing |
| `delete_existing_dirs` | `False` | Overwrite an existing chunk dir on re-export |

Real config files are in the sibling `~/code/ppdb-config` repo
(e.g. `ppdb-dev_config.yaml`, `ppdb-int_config.yaml`) and are deployed to
`gs://ppdb-<env>-config/ppdb-<env>_config.yaml`. In dev/int the tracking DB is
`ppdb` with schema `chunk_tracking`.

### BigQuery datasets (`Datasets`, `DatasetType`)

`staging` → `ppdb_staging`, `promotion` → `ppdb_promotion`, `internal` →
`ppdb_internal`, `public` → `ppdb_public`. See
[architecture § BigQuery datasets](../architecture.md#bigquery-datasets) for
what each holds, who writes and reads it, and access. Use
`config.fqn_for(DatasetType.X, table)` or `TableRefs` to build names; don't
hard-code dataset IDs.

## Environment variables (Cloud Run use)

Read by `PpdbBigQuery.from_env()` / `make_engine()` and `gcp/`:

| Var | Purpose |
|---|---|
| `PPDB_CONFIG_URI` | Config location (required for `from_env`) |
| `CLOUDSQL_ENABLED` | `true` → use Cloud SQL Python Connector instead of `db_url` |
| `CLOUDSQL_INSTANCE_CONNECTION_NAME`, `CLOUDSQL_USER`, `CLOUDSQL_DB_NAME`, `CLOUDSQL_IP_TYPE` (default `private`), `CLOUDSQL_DRIVERNAME` (default `pg8000`) | Connector settings; IAM auth with `<sa>@<project>.iam` users |
| `PPDB_USE_SECRET_MANAGER` | `true` → DB password from Secret Manager |
| `LOG_LEVEL` | `gcp/logging_setup.py` |
| `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `PROJECT_ID`, Cloud Run `K_*`/`CLOUD_RUN_*` | Sentry tagging (`gcp/sentry.py`) |

## Chunk pipeline, step by step

### 1. Export: `ppdb-replication run APDB_CONFIG PPDB_CONFIG`

`Replicator.run()` polls the APDB for replica chunks. It copies a chunk once a
newer chunk exists and `--min-wait-time` has passed, or after
`--max-wait-time`, checking every `--check-interval`. `PpdbBigQuery.store()`:

1. Writes `DiaObject.parquet`, `DiaSource.parquet`, `DiaForcedSource.parquet`
   into `<replication_dir>/<chunk_id>/`, dropping `apdb_replica_subchunk`.
2. If the chunk has APDB update records, writes them as Parquet too (`_handle_updates`).
3. Writes `manifest.json` (`bigquery/manifest.py`: file list, row counts,
   SHA-256 checksums, update-record flag).
4. Inserts a tracking row with status `exported`, or `skipped` if the chunk is empty.

### 2. Upload: `ppdb-replication upload-chunks PPDB_CONFIG`

`ChunkUploader.run()` polls for `status == exported` every `--wait-interval`;
`--upload-interval` throttles between chunks. Per chunk:

1. Uploads the Parquet files listed in the manifest to `gs://<bucket>/<object_prefix>/<id>/`.
2. Uploads `manifest.json`.
3. Sets status `uploaded` and `gcs_uri`.
4. Publishes `{"dataset": <staging>, "chunk_id": "<id>", "folder": "gs://..."}` to `stage_chunk_topic`.

On any failure it deletes the chunk's GCS prefix; the local files stay for debugging.

### 3. Staging: in ppdb-cloud-functions

`stage_chunk` loads into `ppdb_staging` and then publishes status `staged` to
`track-chunk-topic`. See [ppdb-cloud-functions](ppdb-cloud-functions.md).

### 4. Promotion: `ChunkPromoter.promote_chunks()` (`bigquery/chunk_promoter.py`)

`PpdbBigQuery.get_promotable_chunks()` returns the contiguous run of `staged`
chunks after the last `promoted`/`skipped` one. Then:

1. `_copy_staging_to_promotion`: clone internal tables into `ppdb_promotion`
   and insert the staged rows for those chunks.
2. `_fill_diaobject_validity_end`: close out superseded DiaObject versions
   (`resources/config/sql/fill_diaobject_validity_end.sql`).
3. `UpdatesManager.apply_updates`: expand APDB update records and MERGE them
   into the promotion tables (`bigquery/updates/`, `merge_*_updates.sql`).
4. `_copy_promotion_to_internal`: copy each promotion table over internal (`WRITE_TRUNCATE`).
5. `_create_diaobject_latest`: `CREATE OR REPLACE` `ppdb_public.DiaObject`
   with rows where `validityEndMjdTai IS NULL`.
6. `_delete_staged_chunks`: delete those chunks' rows from staging.
7. `_mark_chunks_promoted`: set status `promoted`.
8. `_cleanup` (always): drop the promotion tables.

Any failure raises `ChunkPromotionError`. An empty list raises
`NoPromotableChunksError`, which callers treat as normal.

### Chunk statuses

`ChunkStatus` in `bigquery/ppdb_replica_chunk_extended.py`:
`exported`, `uploaded`, `staged`, `promoted`, `skipped`, `failed`. Nothing in
dax_ppdb or the cloud functions currently sets `failed`. A chunk that never
reaches `staged` blocks promotion of all later chunks.

### SSO data: `ppdb-cli upload-sso-data CONFIG --directory DIR`

`SSOUploader` uploads SSO Parquet files (e.g. SSObject, SSSource,
`mpc_orbits`, `current_identifications`, `numbered_identifications`) to the
SSO ingest bucket under a unique sortable prefix. It then publishes to the
`load_sso` topic. This is separate from chunk replication; the load
**replaces** the internal SSO tables.

## CLIs

| Command | Purpose |
|---|---|
| `ppdb-cli create-sql DB_URL OUT_CONFIG` | Create a SQL-backend PPDB |
| `ppdb-cli create-bq DB_URL OUT_CONFIG` | Create the chunk-tracking DB and write a BigQuery config |
| `ppdb-cli create-datasets CONFIG [--exists-ok] [--configure-authorized-views] [--disable-search-indexes]` | Create BigQuery datasets/tables/views |
| `ppdb-cli upload-sso-data CONFIG --directory DIR` | SSO upload |
| `ppdb-replication run` / `upload-chunks` | See steps 1–2 |
| `ppdb-replication list-chunks-apdb` / `list-chunks-ppdb` | Inspect chunks on either side |

## Packaging and images

- `requirements.txt` + `pyproject.toml`. Depends on `lsst-dax-apdb`,
  `lsst-dax-ppdbx-gcp` (being retired; currently provides the Pub/Sub
  `Publisher` and storage helpers), `lsst-felis`, `lsst-resources`, and
  `lsst.sdm.schemas` for the schema resource.
- `docker/Dockerfile.replication` → `ghcr.io/lsst/ppdb-replication`, built by
  `.github/workflows/docker.yaml` on PRs, `main`, and tags.
- `cloudrun-vX.Y.Z` tags are what ppdb-cloud-functions pins.

## Tests

`tests/test_*.py`: one file per main unit (chunk_promoter, chunk_uploader,
dataset_builder, felis_converter, manifest, ppdb_bigquery, ppdb_sql,
sso_uploader, updates_*). Shared fixtures are in `python/lsst/dax/ppdb/tests/`
(`_ppdb.py`, `_bigquery.py`, `_updates.py`). Test schema:
`resources/config/schemas/test_apdb_schema.yaml`.
