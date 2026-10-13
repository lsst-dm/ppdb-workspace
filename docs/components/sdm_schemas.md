# sdm_schemas reference (PPDB only)

`repos/sdm_schemas` (lsst/sdm_schemas). Written from a code survey at
`911dc22` (2026-10-13). Felis YAML schemas live in `python/lsst/sdm/schemas/`;
`yml/` is a symlink to the same directory.

## PPDB-relevant schemas

| File | Name / version | Role |
|---|---|---|
| `ppdb.yaml` | `ppdb` 10.0.0 | **The PPDB schema.** Tables `DiaObject`, `DiaSource`, `DiaForcedSource`, `SSSource`, `SSObject`, `mpc_orbits`, `current_identifications`, `numbered_identifications` |
| `apdb.yaml` | `ApdbSchema` 10.0.0 | APDB schema. Source of the DIA column definitions |
| `sso_base.yaml` | `sso_base` 10.0.0 | Column dictionary for Solar System tables |
| `dp2_prompt.yaml` | `dp2_prompt` 1.1.1 | The prompt-products tables of Data Preview 2 (DiaSource, DiaObject, ForcedSourceOnDiaObject, SSObject, SSSource, mpc_orbits, current/numbered_identifications), for testing in the PPDB BigQuery database. Columns come from `drp_base.yaml`, matching `dp2.yaml` |
| `dp2.yaml`, `drp_base.yaml` | | Full DP2 schema and its column dictionary |

### How ppdb.yaml is built

`ppdb.yaml` defines almost no columns itself. It declares `resources`
(`apdb: apdb.yaml`, `sso_base: sso_base.yaml`) and each table uses
`columnRefs` to pick columns from those, e.g. `columnRefs.apdb.DiaObject.ra`.
As a result:

- A column change in `apdb.yaml` or `sso_base.yaml` flows into the PPDB
  schema only if `ppdb.yaml` references that column.
- Versions are kept aligned with the APDB (`ppdb` 10.0.0 ↔ `ApdbSchema` 10.0.0).
- PPDB `DiaObject` is described as **latest version only**; its schema
  excludes `validityEndMjdTai`. dax_ppdb adds `validityEndMjdTai` itself in
  the staging and internal datasets, and `geo_point` in internal and public.

## Who consumes these schemas

| Consumer | How |
|---|---|
| dax_ppdb | `PpdbBigQueryConfig.felis_schema_uri` defaults to `resource://lsst.sdm.schemas/ppdb.yaml`, so the installed `lsst-sdm-schemas` package version determines the BigQuery tables `ppdb-cli create-datasets` builds |
| ppdbtap TAP_SCHEMA | `tap-schema/build-all` builds images `idfdev-ppdbtap` and `idfint-ppdbtap` from `ppdb.yaml` |
| `dp2_prompt` BigQuery dataset (int) | Loaded from DP2 prompt tables matching `dp2_prompt.yaml`; ppdbtap int maps `dp2_prompt.*` to `ppdb-int-6c62.dp2_prompt.*` |

`tap-schema/build-all` lists only `ppdb.yaml` for the ppdbtap images, not
`dp2_prompt.yaml`. It's unclear how the `dp2_prompt` TAP_SCHEMA entries for int
are provided.

## Schema change path

`apdb.yaml`/`sso_base.yaml` → `ppdb.yaml` (`columnRefs`) → release of
sdm_schemas → dax_ppdb picks it up (`ppdb-cli create-datasets`, plus any
column changes needed in existing BigQuery tables) → TAP_SCHEMA image rebuild
→ ppdbtap `tableMappings` if tables are added or renamed.

Existing BigQuery tables aren't migrated automatically. `create-datasets`
creates objects; altering live tables is a separate, manual step.

## Validation and CI

- `make check` runs `felis validate yml/*.yaml` (needs `lsst-felis`, which is in `ppdb_env`).
- CI: `validate.yaml`, `validate_extra_checks.yaml`, `test_{sqlite,postgresql,mysql}.yaml`,
  `compare.yaml`, `check_band_columns.yaml`, `build.yaml` (TAP schema images), `docs.yaml`.
- Branches follow `tickets/DM-NNNNN`; releases are weekly tags (`w.YYYY.NN`).
