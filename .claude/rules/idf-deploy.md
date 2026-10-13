---
paths:
  - "repos/idf_deploy/**"
---

# idf_deploy (PPDB parts)

Only `environment/deployments/ppdb/` and `.github/workflows/ppdb-*.yaml` are
PPDB-specific. Shared modules live in `modules/`; changing them affects
other projects.

## Layout

- `environment/deployments/ppdb/`: GCP project (`main.tf`, vars)
- `.../ppdb/cloudsql/`: Cloud SQL Postgres instance for the PPDB
- `.../ppdb/services/`: everything the chunk pipeline uses. One file per
  concern: `gcs.tf`, `pubsub.tf`, `bigquery.tf`, `artifact-registry.tf`,
  `stage-chunk`/`track-chunk`/`promote-chunks`/`load-sso`/`sso-uploader`,
  `dataflow-*.tf`, `cloudrun-*.tf`, `usdf-replication.tf` (access for the
  USDF replication service), `github-ci.tf`, `secrets.tf`
- `.../ppdb/env/{dev,int}{,-cloudsql,-services}.tfvars`: per-environment values.
  No prod tfvars exist yet, though `ppdb-prod-*` workflows do.

## How changes are applied

Workflows `ppdb-{dev,int,prod}-{proj,cloudsql,services}-tf.yaml` call
`_reusable-terraform-plan-apply.yaml`: **plan on PR, apply on push to `main`**.

They trigger **only on changes to the matching `env/*.tfvars` file**, not on
`.tf` changes. A `.tf`-only change is not applied until that environment's
tfvars changes or someone runs the workflow manually.

## Local use

`terraform` is used locally **only to review**, mostly to show plans. Nothing is
applied from a local machine; all applies go through the workflows above.

```bash
cd repos/idf_deploy/environment/deployments/ppdb/services
terraform fmt -check && terraform validate
terraform plan -var-file=../env/dev-services.tfvars
```

`plan` needs GCP credentials and `terraform init` against the remote state
backend (`backend.tf`, state prefix `ppdb/<env>/services`). `apply`,
`destroy`, `import`, and `state` are denied in `.claude/settings.json`.
`terraform` is on the system PATH (not in a conda env).

Full reference: `docs/components/idf_deploy.md`. Read it before non-trivial changes here.
