# PPDB architecture

How data moves from the APDB to users, and which repo owns each piece.
Written from a code survey on 2026-10-13; verify against the code
before relying on details.

## Pipeline

```
USDF (Kubernetes, phalanx: ppdb-replication)            GCP (IDF, idf_deploy: deployments/ppdb)
─────────────────────────────────────────────           ─────────────────────────────────────────────
APDB (Cassandra)
  │  ppdb-replication run         [exporter pod]
  ▼
local Parquet + chunk row ──status: exported──► PPDB chunk table (Cloud SQL Postgres)
  │  ppdb-replication upload-chunks [uploader pod]
  ▼
GCS bucket ─────────────────────status: uploaded
  │  publish → stage-chunk-topic
  ▼
                                                 stage_chunk (Cloud Run) → Dataflow flex job
                                                   │ loads Parquet → BigQuery staging tables
                                                   │ publish → track-chunk-topic
                                                   ▼
                                                 track_chunk (Cloud Run, Eventarc) ─status: staged
                                                   ▼
                                                 Cloud Scheduler → Workflow → promote_chunks
                                                   (Cloud Run job, ChunkPromoter)
                                                   │ staging → promotion (scratch) → internal
                                                   ▼                         ─status: promoted
                                                 ppdb_internal (history) + ppdb_public (views, current DiaObject)
                                                   ▼
                                                 ppdbtap (phalanx, IDF) → TAP/ADQL users
```

## Chunk lifecycle

`ChunkStatus` in `dax_ppdb/.../bigquery/ppdb_replica_chunk_extended.py`:
`exported → uploaded → staged → promoted`, plus `failed` and `skipped`.

Promotion is ordered. `PpdbBigQuery` selects the first contiguous run of
`staged` chunks after the last `promoted`/`skipped` one. A chunk stuck before
`staged` therefore blocks promotion of every later chunk.

## BigQuery datasets

Each PPDB GCP project (`ppdb-dev-5c07`, `ppdb-int-6c62`) has the datasets
below. All are in location `US`. Names come from `Datasets` in
`dax_ppdb/.../bigquery/ppdb_bigquery_config.py` and can be overridden per
config file, though no current config does. Table and view definitions are
generated from the Felis schema (`lsst.sdm.schemas/ppdb.yaml`) by
`ppdb-cli create-datasets` (`bigquery/schema/dataset_builder.py`).

```
             Dataflow (stage_chunk)                   promote_chunks (ChunkPromoter)
Parquet ───────────────────────────► ppdb_staging ─────┐
                                                       ▼
                       ppdb_internal ──CLONE──► ppdb_promotion ──(+ staged rows, validity end,
                             ▲                        │          MERGE updates)
                             └──copy WRITE_TRUNCATE───┘
                             │
                             ├──views──────────────► ppdb_public.{DiaSource, DiaForcedSource, SSO tables}
                             └──current versions───► ppdb_public.DiaObject (table)  ──► ppdbtap
SSO Parquet ──load_sso (temp staging table, then WRITE_TRUNCATE)──► ppdb_internal.{SSO tables}
```

### `ppdb_staging`: landing zone for chunks

- **Contents:** `DiaObject`, `DiaSource`, `DiaForcedSource`, each with an
  extra `apdb_replica_chunk` column (DiaObject also has `validityEndMjdTai`).
  Also `updates`: raw APDB update records as `apdb_replica_chunk`,
  `update_time_ns`, `update_order`, `json_payload`.
- **Written by:** the `stage_chunk` Dataflow job (`WRITE_APPEND`), one chunk at a time.
- **Read by:** promotion, which also deletes each chunk's rows after promoting it.
  At steady state staging holds only chunks that are staged but not yet promoted.
- `load_sso` also creates temporary per-table staging tables here that
  expire after 2 hours.

### `ppdb_promotion`: scratch space for promotion

- **Contents:** nothing persistent. During a promotion run it holds `CLONE`s
  of the internal tables plus the staged rows, and the `expanded_updates` and
  `latest_only` update tables built by `UpdatesManager`.
- **Lifecycle:** filled at the start of `promote_chunks()` and dropped in
  `_cleanup()` whether the run succeeds or fails. Leftover tables here mean a
  promotion crashed hard.
- **Why it exists:** all changes (new rows, closing `validityEndMjdTai`,
  merged updates) are applied to copies. Internal is replaced only after every
  step succeeds, so readers never see a half-promoted state.
- **Not in Terraform.** It's created by `ppdb-cli create-datasets`.

### `ppdb_internal`: full history, source of truth

- **Contents:**
  - DIA tables, each with a `geo_point` GEOGRAPHY column, clustered on it, and
    search indexes on `diaObjectId`.
  - `DiaObject` keeps **every version** of each object, with
    `validityEndMjdTai` (NULL means current).
  - SSO tables: `SSObject`, `SSSource`, `mpc_orbits`,
    `current_identifications`, `numbered_identifications`.
- **Written by:**
  - Promotion only, for DIA tables. Each promotion copies the promotion tables
    over internal with `WRITE_TRUNCATE`.
  - `load_sso`, for SSO tables. This is a full replace on each load.
- **Read by:** public views (authorized views when created with
  `--configure-authorized-views`) and the TAP service account.
- **Description in Terraform:** "target tables for data drop (promotion);
  accessed via views from ppdb_public".

### `ppdb_public`: what users query

- **Contents:**
  - `DiaObject` is a real **table**, rebuilt on each promotion with
    `CREATE OR REPLACE ... WHERE validityEndMjdTai IS NULL`, so it holds only
    current versions. It has `geo_point` with clustering and a `diaObjectId`
    search index. It's a table because a filtering view would be slow, and a
    materialized view would break on the internal table swaps.
  - Views selecting the schema columns from internal: `DiaSource`,
    `DiaForcedSource`, and the five SSO tables. Internal-only columns like
    `geo_point` are hidden this way.
- **Read by:** `ppdbtap` through `bigquery-kafka`. ppdbtap's `tableMappings`
  in phalanx map TAP names `ppdb.<Table>` to `<project>.ppdb_public.<Table>`.

### `ppdb_backup`

- Created by Terraform (description "Backups"). Nothing in dax_ppdb or
  ppdb-cloud-functions currently writes to it.

### Other datasets

- `dp2_prompt` (int only): the prompt-products tables from Data Preview 2.
  The schema is `dp2_prompt.yaml` in sdm_schemas, which takes those tables'
  columns from `dp2.yaml`/`drp_base.yaml` (DiaSource, DiaObject,
  ForcedSourceOnDiaObject, SSObject, SSSource, mpc_orbits,
  current/numbered_identifications). It's exposed through ppdbtap as `dp2_prompt.*` and granted to the TAP SA by
  `bigquery_tap_extra_datasets` in `int-services.tfvars`. It isn't part of the
  chunk pipeline.

### Access

| Principal | Access |
|---|---|
| TAP SA (`bigquery-kafka@science-platform-<env>-*`) | dataViewer on `ppdb_public`, `ppdb_internal`, extra datasets; project jobUser + readSessionUser |
| `stage_chunk` Dataflow SA | BigQuery dataEditor + jobUser (project) |
| `cloudrun-promote-chunks` SA | dataEditor + jobUser (project), explicit access on `ppdb_staging` |
| `load_sso` Dataflow SA | dataEditor + jobUser (project) |

Time travel is 168 hours (7 days) on all Terraform-managed datasets
(`bigquery_max_time_travel_hours`). This is the main recovery path if a
promotion writes bad data into internal.

## Who owns what

| Concern | Code | Deployment/config |
|---|---|---|
| Replication, export, upload | `dax_ppdb` (`replicator.py`, `bigquery/chunk_uploader.py`) | `phalanx/applications/ppdb-replication` |
| Staging load | `ppdb-cloud-functions/stage_chunk` | CI workflow + `idf_deploy/.../services/{trigger-stage-chunk,dataflow-stage-chunk}.tf` |
| Status tracking | `ppdb-cloud-functions/track_chunk` | CI workflow + `.../services/track-chunk.tf` |
| Promotion | `dax_ppdb/bigquery/chunk_promoter.py`, `ppdb-cloud-functions/promote_chunks` | CI workflow + `.../services/promote-chunks.tf` (scheduler) |
| SSO load | `dax_ppdb/bigquery/sso_uploader.py`, `ppdb-cloud-functions/load_sso` | `.../services/{load-sso,sso-uploader,dataflow-load-sso}.tf` |
| GCP resources (buckets, topics, datasets, IAM, Cloud SQL) | none | `idf_deploy/environment/deployments/ppdb/` |
| Table schemas (PPDB, APDB, SSO, DP2 prompt) | `sdm_schemas` (`ppdb.yaml`, `apdb.yaml`, `sso_base.yaml`, `dp2_prompt.yaml`) | Consumed by dax_ppdb `create-datasets`; released as `lsst.sdm.schemas` |
| TAP_SCHEMA for ppdbtap | `sdm_schemas/tap-schema/build-all` (`idf{dev,int}-ppdbtap` from `ppdb.yaml`) | Image used by `phalanx/applications/ppdbtap` |
| TAP service | CADC TAP (external) | `phalanx/applications/ppdbtap` |

## Cross-repo change checklist

- **New or changed config/env var for a function:** function `main.py` +
  its deploy workflow + `idf_deploy` resource or IAM if it touches a new resource.
- **dax_ppdb change used by the functions:** tag `cloudrun-vX.Y.Z` in dax_ppdb,
  then bump `requirements*.txt` in each function.
- **dax_ppdb CLI/config change:** check `phalanx/applications/ppdb-replication`
  templates and values.
- **Schema change:** `sdm_schemas` (`apdb.yaml`/`sso_base.yaml` → `ppdb.yaml`) → dax_ppdb `bigquery/schema` → BigQuery
  tables (staging, internal, public) → TAP_SCHEMA image (`tap-schema/build-all`) → ppdbtap tableMappings.

## External dependencies

- `dax_apdb`: replication source (`ApdbReplica`, `ReplicaChunk`).
- `sdm_schemas` (submodule): source of every table definition. The BigQuery
  tables, the TAP_SCHEMA and the APDB itself all derive from its Felis YAML.
  See [components/sdm_schemas.md](components/sdm_schemas.md).
- `dax_ppdbx_gcp`: GCP helpers, e.g. `lsst.dax.ppdbx.gcp.pubsub.Publisher` in
  `chunk_uploader.py`. **Being retired**: move code into dax_ppdb rather than
  extending it.
