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
- `gcp/`: GCP helpers (GCS, Pub/Sub `Publisher`) and Cloud Run helpers (logging, Sentry, CloudEvents). Imported by `ppdb-cloud-functions`.
- `replicator.py`: APDB → PPDB replication loop
- `cli/`, `scripts/`: `ppdb-cli` and `ppdb-replication` (`run`, `upload-chunks`, `list-chunks-apdb`, `list-chunks-ppdb`)

## Build and test

Use the `ppdb_env` conda env (`conda run -n ppdb_env ...`). Tests that touch
GCP must run against the dev project `ppdb-dev-5c07`, never int (`ppdb-int-6c62`).
Check with `gcloud config get-value project` first.

```bash
cd repos/dax_ppdb
conda run -n ppdb_env pip install -r requirements.txt   # dependencies (when they change)
conda run -n ppdb_env pip install --no-deps .           # build/install the package
conda run -n ppdb_env pytest -n auto tests/
```

Reinstall with `pip install --no-deps .` after code changes before running
tests or CLIs. It's a regular install, not editable. Run the tests after
changing code.

- One module: `conda run -n ppdb_env pytest -v tests/test_module.py`
- One test: `conda run -n ppdb_env pytest -v tests/test_module.py::test_function`

Errors about missing modules usually mean the package or its requirements
aren't installed in `ppdb_env`. If `pip install -r requirements.txt` or the
env itself fails, stop and ask instead of repairing the environment.

Coverage for one module, on request (adjust `--source` and the test module):

```bash
cd repos/dax_ppdb
conda run -n ppdb_env python -m coverage erase
conda run -n ppdb_env env PYTHONPATH="$PWD/python" python -m coverage run \
  --source=lsst.dax.ppdb.bigquery.schema.dataset_builder \
  -m unittest -v tests.test_dataset_builder
conda run -n ppdb_env python -m coverage report -m
conda run -n ppdb_env python -m coverage xml
```

CI (`.github/workflows/build.yaml`) installs `requirements.txt`, pytest,
pytest-xdist, then `uv pip install --no-deps -e .`. It also installs `postgresql` from conda-forge for the SQL tests, and authenticates
to GCP, so some BigQuery tests may need credentials or skip without them.

Lint/format: `ruff check --fix`, `ruff format` (line length 110), numpydoc
docstring validation, `mypy`. All are run by `pre-commit`.

## Code style

- **License header:** every Python module, tests included, starts with the
  GPL header in `.claude/templates/license-header.txt`, with `{project}`
  set to `dax_ppdb`. Copy it into new files, and don't alter it in existing ones.
- **Type hints** on all new or changed function parameters and returns.
- **Docstrings** (numpydoc, triple double quotes) for new or substantially
  changed public modules, classes and functions:
  - Closing quotes go on their own line in multi-line docstrings. If the
    summary line plus closing quotes would pass 80 characters, move the last
    word and the quotes to the next line.
  - Sections: `Parameters` (types optional), `Returns` (with type),
    `Raises` (each entry starts "Raised if"), `Notes` (sparingly).
- **Comments:** no "we" or "I".

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
