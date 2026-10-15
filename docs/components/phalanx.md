# phalanx reference (PPDB only)

`repos/phalanx`. Written from a code survey at `901d6f0` (2026-10-13).
Only PPDB-related apps are covered here.

## Apps and where they run

| App | Environments | Role |
|---|---|---|
| `ppdb-replication` | `usdfdev`, `usdfint`, `usdfprod` | APDB → Parquet export and GCS upload (dax_ppdb) |
| `ppdbtap` | `idfdev`, `idfint` | TAP service over BigQuery `ppdb_public` |
| `bigquery-kafka` | `idfdev`, `idfint` | Query worker for ppdbtap (source: lsst-sqre/qserv-kafka) |
| `sasquatch` subchart `charts/ppdbtap` | `idfdev`, `idfint` | Kafka topics/users `lsst.ppdbtap.job-{run,status,delete}` |
| `repertoire` | all RSP envs; PPDB parts in `idfdev`, `idfint` | Service discovery: the `prompt` dataset, ppdbtap's URL, and the ppdbtap TAP_SCHEMA contents |

Apps are enabled in `environments/values-<env>.yaml`.

## ppdb-replication

Chart `applications/ppdb-replication/`. Image `ghcr.io/lsst/ppdb-replication`,
tag `main`, `pullPolicy: Always`, so a restart picks up the latest dax_ppdb `main`.

Two deployments from the same image:

| Template | Command | Key flags (values) |
|---|---|---|
| `exporter-deployment.yaml` | `ppdb-replication run <apdbConfig> <ppdbConfig>` | `--min-wait-time` (60), `--max-wait-time` (3600), `--check-interval` (300) |
| `uploader-deployment.yaml` | `ppdb-replication upload-chunks <ppdbConfig>` | `--wait-interval` (300), `--upload-interval` (0) |

Per-environment values:

| Env | APDB config | PPDB config | Cloud SQL | Overrides |
|---|---|---|---|---|
| usdfdev | `/sdf/data/rubin/user/jeremym/ppdb-config/apdb_dev.yaml` | `gs://ppdb-dev-config/ppdb-dev_config.yaml` | `ppdb-dev-5c07:us-central1:ppdb-dev`, user `usdf-replication@ppdb-dev-5c07.iam` | `logProfile: development`, check/wait intervals 60 |
| usdfint | `s3://embargo@rubin-summit-users/apdb_config/cassandra/pp_apdb_lsstcam.yaml` | `gs://ppdb-int-config/ppdb-int_config.yaml` | `ppdb-int-6c62:us-central1:ppdb-int`, user `usdf-replication@ppdb-int-6c62.iam` | `uploadInterval: 480` (test throttle for BigQuery rate limits) |
| usdfprod | same as int | `/sdf/data/rubin/user/jeremym/ppdb-config/ppdb_lsstcam.yaml` | not set (connectionName empty) | Older config with a direct `db_url` and GCP project `ppdb-prod`, which is not managed by idf_deploy's ppdb deployment |

Runtime wiring:

- **Mounts:** `/sdf/group/rubin`, `/sdf/data/rubin` and `/sdf/scratch` via PVCs.
  `replication_dir` in the PPDB config is under `/sdf/scratch/rubin/ppdb/data/<env>`.
- **Secrets** (Vault, mounted at `/app/secrets`):
  - `aws-credentials.ini`: S3 access to the APDB config
  - `db-auth.yaml`: Cassandra (`LSST_DB_AUTH`)
  - `postgres-credentials.txt`: `PGPASSFILE`
  - `gcp-credentials.json`: `GOOGLE_APPLICATION_CREDENTIALS`, the
    `usdf-replication` SA key. It's referenced by the templates but **not
    listed in `secrets.yaml`**.
- **Env:** `CLOUDSQL_*` from `config.cloudSql`, `DAX_APDB_INDEX_URI`
  (ConfigMap), S3 endpoint/profile vars, `DAX_APDB_MONITOR_CONFIG` (metrics to logs).
- **Cloud SQL:** `ipType: public`, because USDF has no interconnect to GCP.
- Also defines a service on port 8080 with an ingress at `/ppdb-replication`, plus a network policy.

## ppdbtap

Chart `applications/ppdbtap/`, a wrapper around `charts/cadc-tap` with `backend: bigquery`.

- **Query path:** TAP request → ppdbtap publishes to Kafka
  `lsst.ppdbtap.job-run` → `bigquery-kafka` runs the query in BigQuery as
  `bigquery-kafka@science-platform-<env>-*.iam` → status on
  `lsst.ppdbtap.job-status`. idf_deploy grants that SA access to `ppdb_public`
  and `ppdb_internal`. The views need internal access.
- **Table mappings:** `tableMappings` maps TAP names to BigQuery tables:
  - dev: `ppdb.{DiaObject,DiaSource,DiaForcedSource,SSObject,SSSource,current_identifications,mpc_orbits,numbered_identifications}` → `ppdb-dev-5c07.ppdb_public.*`
  - int: `ppdb.{DiaObject,DiaSource,DiaForcedSource}` → `ppdb-int-6c62.ppdb_public.*`,
    plus `dp2_prompt.*` (DiaObject, DiaSource, ForcedSourceOnDiaObject, SSObject,
    SSSource, mpc_orbits, current_identifications, numbered_identifications) → `ppdb-int-6c62.dp2_prompt.*`.
  - Adding a public table means adding a mapping in each env's values file.
- **UWS and TAP_SCHEMA databases:** Cloud SQL database `ppdbtap` on the
  **science-platform** instance, not the PPDB one. SA `ppdbtap@science-platform-<env>-*`.
- **Secrets:** `uws-db-password`, `tap-schema-password`, `google_creds.json`
  (async results to GCS), and `sentry-dsn` if enabled.

## repertoire

Chart `applications/repertoire/`, owned by SQuaRE and shared by all RSP
services. The PPDB-related parts:

- **Datasets:** `prompt` ("Prompt products", docs `prompt-products.lsst.io`)
  is listed in `config.availableDatasets` for `idfdev` and `idfint`, and
  `config.rules.ppdbtap` maps it to `https://<host>/api/ppdbtap`. The
  `prompt` ObsCore config comes from `lsst-dm/dax_obscore` `configs/prompt.yaml`.
- **TAP_SCHEMA:** `config.tap.servers.ppdbtap` lists the sdm_schemas schemas
  that repertoire loads into ppdbtap's TAP_SCHEMA. Default schemas are
  `ppdb`, database `ppdbtap` (key `ppdbtap-database-password`), disabled
  unless an env enables it. Per env:
  - idfdev: enabled, `schemaVersion: releases/w.2026.38`
  - idfint: enabled, `schemaVersion: tickets/DM-52639`, schemas `ppdb` and `dp2_prompt`
- **Schema source:** `config.tap.schemaSourceTemplate`, by default
  `gs://rubin-sdm-schemas-artifacts/{version}/schemas.tar.gz`. A
  TAP_SCHEMA change therefore needs a published sdm_schemas artifact and a
  `schemaVersion` bump here.
- **Cloud SQL:** reaches the science-platform instance as
  `repertoire@science-platform-<env>-*.iam`.

## Editing conventions

- Use the `phalanx_env` conda env.
- `README.md` and `docs/applications/<app>/values.md` are generated by
  helm-docs from `# --` comments. Edit `values.yaml` and run pre-commit.
- Upstream is lsst-sqre/phalanx, so SQuaRE reviews PRs. Argo CD deploys after merge.
