---
paths:
  - "repos/sdm_schemas/**"
---

# sdm_schemas (PPDB parts)

Only these files matter for PPDB work (`python/lsst/sdm/schemas/`, also `yml/`):
`ppdb.yaml`, `apdb.yaml`, `sso_base.yaml`, `dp2_prompt.yaml` (with
`dp2.yaml`/`drp_base.yaml`), and the `ppdbtap` lines in `tap-schema/build-all`.
The other schemas belong to other teams.

- `ppdb.yaml` uses `columnRefs` into `apdb.yaml` and `sso_base.yaml` instead of
  defining columns. Change the source schema, then reference the column here.
- Keep the `ppdb` version aligned with `ApdbSchema`.
- PPDB `DiaObject` is latest-version-only and has no `validityEndMjdTai`.
  dax_ppdb adds internal-only columns itself.
- Validate with `conda run -n ppdb_env felis validate python/lsst/sdm/schemas/ppdb.yaml`
  (or `make check` for everything).
- A schema change usually also needs dax_ppdb and BigQuery table updates and a
  TAP_SCHEMA rebuild. See the change path in the reference doc.

Full reference: `docs/components/sdm_schemas.md`. Read it before non-trivial changes here.
