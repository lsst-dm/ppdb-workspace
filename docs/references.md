# References

## Documentation sites

| Site | Notes |
|---|---|
| [BigQuery](https://docs.cloud.google.com/bigquery/docs) | Google Cloud |
| [Cloud Run](https://docs.cloud.google.com/run/docs/) | Google Cloud |
| [Pub/Sub](https://docs.cloud.google.com/pubsub/docs) | Google Cloud |
| [Sentry](https://docs.sentry.io/) | Error monitoring |
| [lsst.io](https://www.lsst.io/) | General Rubin documentation: technical and developer docs |
| [LSST Developer Guide](https://developer.lsst.io/) | DM development practices |
| [DM Technotes](https://www.lsst.io/dmtn/) | DMTN technical notes |
| [Documenteer](https://documenteer.lsst.io/) | Rubin documentation tooling |
| [Phalanx](https://phalanx.lsst.io/) | Rubin Kubernetes service deployment |
| [dax_ppdb](https://dax-ppdb.lsst.io/) | Package documentation (minimal for now) |
| [SDM Schemas](https://sdm-schemas.lsst.io/) | Schema browser |
| [data-int](https://data-int.lsst.cloud/) | Rubin Science Platform integration environment |

## GitHub repositories

### PPDB components

| Repository | Notes |
|---|---|
| [lsst/dax_apdb](https://github.com/lsst/dax_apdb) | Interface to the Alert Production Database (Cassandra), whose data is replicated to the PPDB |
| [lsst/dax_ppdb](https://github.com/lsst/dax_ppdb) | Core PPDB Python package: replication, chunk upload, BigQuery promotion |
| [lsst-dm/ppdb-cloud-functions](https://github.com/lsst-dm/ppdb-cloud-functions) | Cloud Run functions and Dataflow jobs for loading chunks into BigQuery |
| [lsst/idf_deploy](https://github.com/lsst/idf_deploy) | Terraform for the GCP projects; PPDB under `environment/deployments/ppdb/` |
| [lsst-sqre/phalanx](https://github.com/lsst-sqre/phalanx) | RSP Helm charts for Argo CD; PPDB apps `ppdb-replication` and `ppdbtap`, and `repertoire` for schema, dataset and TAP_SCHEMA configuration |
| [lsst/sdm_schemas](https://github.com/lsst/sdm_schemas) | Felis schemas: `ppdb.yaml`, `apdb.yaml`, `sso_base.yaml`, `dp2_prompt.yaml` |

### Other

| Repository | Notes |
|---|---|
| [conda-forge/rubinenv-feedstock](https://github.com/conda-forge/rubinenv-feedstock) | Conda-forge recipe for `rubin-env`, Rubin's standard Python environment |
| [mjuric/ssp-tools](https://github.com/mjuric/ssp-tools) | Solar System daily data products pipeline |
