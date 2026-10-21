# idf_deploy reference (PPDB only)

`repos/idf_deploy/environment/deployments/ppdb/`. Written from a code survey
at `222b236` (2026-10-13). Non-PPDB parts of idf_deploy are out of scope.

## Three Terraform roots, applied in order

| Root | State prefix | tfvars | Creates |
|---|---|---|---|
| `ppdb/` (project) | `ppdb/<env>` | `env/<env>.tfvars` | GCP project, VPC `ppdb-<env>-vpc`, subnet `subnet-us-central1-01`, budget, IAM |
| `ppdb/cloudsql/` | `ppdb/<env>/cloudsql` | `env/<env>-cloudsql.tfvars` | Postgres instance `ppdb-<env>` with database `ppdb`, private service access, IAM group users |
| `ppdb/services/` | `ppdb/<env>/services` | `env/<env>-services.tfvars` | Everything else (below) |

State bucket: `lsst-terraform-state`. `services/main.tf` reads outputs from
the project and cloudsql states, and from `science-platform/<env>/cloudsql`
to get the `bigquery-kafka` service account used by TAP.

## Environments

| Env | Project ID | Notes |
|---|---|---|
| dev | `ppdb-dev-5c07` | Cloud SQL backups off; GitHub CI service account enabled (`create_gh_ci_sa`) |
| int | `ppdb-int-6c62` | Backups + PITR on; extra TAP dataset `dp2_prompt` (`bigquery_tap_extra_datasets`) |
| prod | none yet | `ppdb-prod-*` workflows exist, but there are no `env/prod*.tfvars` |

Both envs: region `us-central1`, Cloud SQL `db-custom-2-8192` ENTERPRISE, and
DB access for `gcp-ppdb-administrators@lsst.cloud`.

## services/ resources by file

| File | What |
|---|---|
| `gcs.tf` | Buckets `ppdb-<env>-config` (PPDB YAML configs), `-dataflow` (templates, temp), `-export`, `-ingest` (chunk uploads), `-sso-ingest` |
| `pubsub.tf` | Topics `stage-chunk-topic`, `track-chunk-topic`, `load-sso-topic`, and dead-letter topics `stage-chunk-dlt`, `track-chunk-dlt` |
| `bigquery.tf` | Datasets `ppdb_staging`, `ppdb_internal`, `ppdb_public`, `ppdb_backup` (location US). TAP SA (`bigquery-kafka`): jobUser + readSessionUser on the project, dataViewer on public, internal, and any extra datasets |
| `trigger-stage-chunk.tf` | Function `trigger-stage-chunk`, its SA, Eventarc trigger on `stage-chunk-topic`, permission to launch Dataflow as the stage-chunk Dataflow SA |
| `dataflow-stage-chunk.tf` | Dataflow worker SA: read ingest bucket, BigQuery data editor/job user, publish to `track-chunk-topic` |
| `track-chunk.tf` | Function `track-chunk`, SA `cloudrun-track-chunks` (Cloud SQL IAM user), Eventarc trigger on `track-chunk-topic`, VPC egress, env vars |
| `promote-chunks.tf` | Cloud Run job `promote-chunks`, SA `cloudrun-promote-chunks` (BQ editor, staging dataset access, Cloud SQL IAM user), Workflow `trigger-promote-chunks-cloudrun-job-workflow`, Cloud Scheduler `schedule-promote-chunks-workflow-job` |
| `load-sso.tf`, `dataflow-load-sso.tf`, `sso-uploader.tf` | SSO path: function, Dataflow SA, uploader SA (write `-sso-ingest`, publish `load-sso-topic`) |
| `usdf-replication.tf` | SA `usdf-replication` used by phalanx `ppdb-replication` at USDF: objectUser on `-ingest`, viewer on `-config`, publish `stage-chunk-topic`, Cloud SQL client + IAM DB user |
| `cloudrun-build.tf`, `cloudrun-deploy.tf` | SAs used to build and deploy functions (the deploy SA is what ppdb-cloud-functions CI uses) |
| `artifact-registry.tf` | Docker repo `ppdb-repo` |
| `github-ci.tf` | Optional CI SA: BigQuery editor/job user, storage admin (dax_ppdb tests) |
| `secrets.tf` | Secret `SENTRY_DSN` + accessor bindings |
| `SQL/iam-sa-permissions.sql` | **Applied manually.** Postgres grants on schema `chunk_tracking` for the IAM users above. Written for dev (`ppdb-dev-5c07`) |

## Function and job configuration

- Functions are `google_cloudfunctions2_function` built from a placeholder zip,
  with `lifecycle { ignore_changes = [build_config[0].source] }`. The real
  code is deployed by ppdb-cloud-functions CI.
- The promote job uses image `hello-job` as a placeholder in the same way.
- Terraform owns env vars, for example on `track-chunk`:
  `PPDB_CONFIG_URI=gs://ppdb-<env>-config/ppdb-<env>_config.yaml`,
  `CLOUDSQL_ENABLED=true`, `CLOUDSQL_IP_TYPE=private`,
  `CLOUDSQL_INSTANCE_CONNECTION_NAME=<project>:us-central1:ppdb-<env>`,
  `CLOUDSQL_USER=<sa>@<project>.iam`, `PROJECT_ID`, `SENTRY_ENVIRONMENT=ppdb-<env>`,
  and `SENTRY_DSN` from Secret Manager.
- Promotion schedule: `promote_chunks_schedule`, default `"0 12 * * *"`
  (daily), with a configurable time zone.

## Not managed here

- The `ppdb_promotion` dataset. dax_ppdb `ppdb-cli create-datasets` creates it,
  along with the tables, views and search indexes in all datasets.
- Postgres schema and tables (`chunk_tracking`), created by `ppdb-cli create-bq`
  (see [chunk tracking database](../chunk-tracking-db.md)).
- Config file contents in `ppdb-<env>-config`, maintained in the sibling `ppdb-config` repo.

## Workflows

`.github/workflows/ppdb-{dev,int,prod}-{proj,cloudsql,services}-tf.yaml` →
`_reusable-terraform-plan-apply.yaml`. These **plan on PR and apply on push to
`main`**, and trigger **only when the matching `env/*.tfvars` changes**. A
`.tf`-only change waits for a tfvars change or a manual
`workflow_dispatch` with `apply_on_workflow_dispatch`.

Locally, terraform is used only for `fmt`/`validate`/`plan`.
