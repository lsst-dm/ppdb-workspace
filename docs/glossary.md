# Glossary

| Term | Meaning |
|---|---|
| **APDB** | Alert Production Database. Operational database written by Alert Production at USDF; source of PPDB data. Code: `dax_apdb`. |
| **PPDB** | Prompt Products Database. User-facing copy of prompt data products, served from BigQuery on GCP. Code: `dax_ppdb`. |
| **Replica chunk** | A time-windowed batch of APDB changes recorded for replication (`ReplicaChunk` in dax_apdb). The unit of work through the whole pipeline. |
| **Chunk status** | `exported`, `uploaded`, `staged`, `promoted`, `failed`, `skipped`. See `docs/architecture.md`. |
| **BigQuery datasets** | `ppdb_staging` (loaded, not yet promoted), `ppdb_promotion` (scratch during promotion), `ppdb_internal` (full history), `ppdb_public` (TAP-facing views + current DiaObject), `ppdb_backup`. |
| **Promotion** | Moving contiguous staged chunks into `ppdb_internal` (via scratch tables in `ppdb_promotion`) and refreshing `ppdb_public.DiaObject` (`ChunkPromoter`). |
| **DiaObject / DiaSource / DiaForcedSource** | Difference-image objects, detections, and forced photometry: the main APDB/PPDB tables. |
| **SSO** (SSObject / SSSource) | Solar System Objects. Loaded through a separate path (`sso_uploader`, `load_sso`). |
| **USDF** | US Data Facility at SLAC. Runs the APDB and `ppdb-replication`. |
| **IDF** | Interim Data Facility on Google Cloud. Hosts the PPDB GCP projects and `ppdbtap`. |
| **dev / int / prod** | GCP environments: `ppdb-dev-5c07`, `ppdb-int-6c62`. Prod is not yet defined in idf_deploy tfvars (usdfprod replication still uses an older `ppdb-prod` config). |
| **Phalanx** | Rubin's Argo CD/Helm config repo for Kubernetes services. |
| **TAP / ADQL** | IVOA query protocol and language used by `ppdbtap`. |
| **Felis** | YAML schema description format and tool; schemas live in `sdm_schemas`. |
| **Flex template** | Dataflow template packaged as a container; used by `stage_chunk` and `load_sso`. |
| **`cloudrun-vX.Y.Z`** | dax_ppdb git tags that the cloud functions pin. |
