# Chunk tracking database

The chunk tracking tables live in Cloud SQL Postgres: database `ppdb`, schema
`chunk_tracking`, one instance per environment. The schema and tables are
created by hand with `ppdb-cli create-bq`, and the grants are applied by hand.
Neither is managed by idf_deploy.

| Env | Project | Instance connection name |
|---|---|---|
| dev | `ppdb-dev-5c07` | `ppdb-dev-5c07:us-central1:ppdb-dev` |
| int | `ppdb-int-6c62` | `ppdb-int-6c62:us-central1:ppdb-int` |
| prod | `ppdb-prod-84a4` | `ppdb-prod-84a4:us-central1:ppdb-prod` |

## Setup (one time)

Install the Cloud SQL Auth Proxy somewhere on your `PATH`. The version in the
URL is hard-coded; check for a newer one.

```bash
cd ~/.local/bin
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.23.0/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy
```

Authenticate and select the project:

```bash
gcloud auth application-default login
gcloud config set project <project>
```

## Connect

Start the proxy with IAM database authentication. Use a non-default port if
something else already listens on 5432.

```bash
cloud-sql-proxy --port 5432 --auto-iam-authn <connection-name> &> cloud-sql-proxy.log &
```

Connect as your `@lsst.cloud` user with the `ppdb` role:

```bash
psql "host=127.0.0.1 port=5432 user=<user>@lsst.cloud dbname=ppdb sslmode=disable options='-c role=ppdb'"
```

The same connection as a SQLAlchemy URL, for `ppdb-cli`. The `@` in the user
name must be escaped as `%40`:

```bash
export DB_URL="postgresql://<user>%40lsst.cloud@127.0.0.1:5432/ppdb?sslmode=disable&options=-c%20role%3Dppdb"
```

## Create the schema

With dax_ppdb installed (`ppdb_env`) and the proxy running:

```bash
ppdb-cli create-bq --replication-dir=/tmp --bucket-name=fake --project-id=fake \
  --object-prefix=fake --db-schema chunk_tracking "$DB_URL" fake_config.yaml \
  --no-validate-config
```

Only the database tables matter here. The BigQuery options are placeholders,
and the config file it writes (`fake_config.yaml`) is thrown away.

## Grants

Each service account that reads or writes chunk status needs grants on
`chunk_tracking`, as an IAM database user (`<sa>@<project>.iam`):

| Service account | Used by |
|---|---|
| `usdf-replication` | phalanx `ppdb-replication` (export and upload) |
| `cloudrun-promote-chunks` | `promote_chunks` |
| `cloudrun-track-chunks` | `track_chunk` |
| `cloudrun-trigger-stage-chunk` | `stage_chunk` (`SELECT, UPDATE` only) |

The grants for each account follow this pattern, shown for prod:

```sql
GRANT USAGE ON SCHEMA chunk_tracking TO "usdf-replication@ppdb-prod-84a4.iam";
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA chunk_tracking
  TO "usdf-replication@ppdb-prod-84a4.iam";
ALTER DEFAULT PRIVILEGES IN SCHEMA chunk_tracking
  GRANT SELECT, INSERT ON TABLES TO "usdf-replication@ppdb-prod-84a4.iam";
```

The dev version of these grants is in idf_deploy
`environment/deployments/ppdb/services/SQL/iam-sa-permissions.sql`.
