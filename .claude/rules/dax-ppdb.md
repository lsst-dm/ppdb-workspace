---
paths:
  - "repos/dax_ppdb/**"
---

# dax_ppdb

Core package `lsst.dax.ppdb` (`python/lsst/dax/ppdb/`).

## Layout

- `ppdb.py`, `ppdb_config.py`, `_factory.py`: `Ppdb` interface and config
- `sql/`: SQL (Postgres) PPDB backend
- `bigquery/`: BigQuery backend and chunk pipeline
  - `ppdb_bigquery.py`: chunk tracking table, Parquet export, promotable-chunk query
  - `ppdb_replica_chunk_extended.py`: `ChunkStatus` (exported → uploaded → staged → promoted; also failed, skipped)
  - `chunk_uploader.py`: `upload-chunks` loop (GCS upload, Pub/Sub publish)
  - `chunk_promoter.py`: staging → internal/public promotion (used by the `promote_chunks` Cloud Run job)
  - `sso_uploader.py`, `updates/`, `schema/`
- `gcp/`: Cloud Run helpers (logging, Sentry, CloudEvents). Imported by `ppdb-cloud-functions`.
- `replicator.py`: APDB → PPDB replication loop
- `cli/`, `scripts/`: `ppdb-cli` and `ppdb-replication` (`run`, `upload-chunks`, `list-chunks-apdb`, `list-chunks-ppdb`)

## Build and test

Use the `ppdb_env` conda env (`conda run -n ppdb_env ...`). Tests that touch
GCP must run against the dev project `ppdb-dev-5c07`, never int (`ppdb-int-6c62`).
Check with `gcloud config get-value project` first.

```bash
cd repos/dax_ppdb
conda run -n ppdb_env pytest -n auto tests/
```

CI (`.github/workflows/build.yaml`) installs `requirements.txt`, pytest,
pytest-xdist, then `uv pip install --no-deps -e .`. It also installs `postgresql` from conda-forge for the SQL tests, and authenticates
to GCP, so some BigQuery tests may need credentials or skip without them.

Lint/format: `ruff check --fix`, `ruff format` (line length 110), numpydoc
docstring validation, `mypy`. All are run by `pre-commit`.

## Cross-repo impact

- `ppdb-cloud-functions` installs this package from a **git tag**
  (`lsst-dax-ppdb @ git+https://github.com/lsst/dax_ppdb@cloudrun-vX.Y.Z`).
  Changes used by the functions need a new `cloudrun-v*` tag and a bump of
  each function's `requirements.txt`.
- The `ppdb-replication` image (`ghcr.io/lsst/ppdb-replication`) is built
  from this repo by `.github/workflows/docker.yaml`; phalanx deploys tag
  `main` by default.
- Changing a CLI flag or config key can break `phalanx/applications/ppdb-replication`
  templates and values.

Full reference: `docs/components/dax_ppdb.md`. Read it before non-trivial changes here.
