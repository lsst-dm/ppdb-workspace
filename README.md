# ppdb-workspace

Workspace for AI-assisted development on the Rubin Observatory
**Prompt Products Database (PPDB)**. This repo holds no product code. It
collects the PPDB component repos as git submodules and carries the shared
Claude Code context (`CLAUDE.md`, `.claude/`) and cross-repo notes.

## Components

| Path | Upstream | What it is |
|---|---|---|
| `repos/dax_ppdb` | [lsst/dax_ppdb](https://github.com/lsst/dax_ppdb) | Core PPDB Python package: replication, chunk upload, BigQuery promotion |
| `repos/ppdb-cloud-functions` | [lsst-dm/ppdb-cloud-functions](https://github.com/lsst-dm/ppdb-cloud-functions) | Cloud Run functions and Dataflow jobs for loading chunks into BigQuery |
| `repos/idf_deploy` | [lsst/idf_deploy](https://github.com/lsst/idf_deploy) | Terraform for the GCP projects (PPDB under `environment/deployments/ppdb/`) |
| `repos/phalanx` | [lsst-sqre/phalanx](https://github.com/lsst-sqre/phalanx) | Kubernetes app configs (`ppdb-replication`, `ppdbtap`) |
| `repos/sdm_schemas` | [lsst/sdm_schemas](https://github.com/lsst/sdm_schemas) | Felis schemas (`ppdb.yaml`, `apdb.yaml`, `dp2_prompt.yaml`) |

See [`CLAUDE.md`](CLAUDE.md) for how the pieces fit together.

## Setup

```bash
git clone --recurse-submodules https://github.com/lsst-dm/ppdb-workspace.git
cd ppdb-workspace
```

If you cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

`idf_deploy` and `phalanx` are configured as shallow clones because only a
small part of each is PPDB-related. Run `git -C repos/<name> fetch --unshallow`
if you need full history.

Open `ppdb.code-workspace` in VS Code for a multi-root view of all components.

## Working with submodules

```bash
# Branch and dirty state across all repos
git submodule foreach 'git status -sb'

# Move every submodule to the latest upstream main
git submodule update --remote

# Start ticket work in one component
git -C repos/dax_ppdb switch -c tickets/DM-NNNNN
```

Commit inside the submodule first. Then commit the updated submodule pointer
here, but only when the workspace should track that revision.

## Claude Code

- `CLAUDE.md` holds the system overview, component map, data flow, and conventions.
- `.claude/rules/` holds per-component guidance, loaded when working in that repo.
- `docs/` holds architecture and glossary; `notes/tickets/` holds per-ticket working notes.
- `CLAUDE.local.md` (gitignored) is for personal context.
- `.claude/hooks/session-start.sh` runs when a Claude session starts. It warns
  if the active gcloud project isn't `ppdb-dev-5c07` and gives Claude a
  branch/dirty summary of each submodule.
- `.claude/settings.json` holds shared permissions. Read-only git, `terraform plan`,
  and `bq show/ls` are pre-approved. Pushes, Terraform apply/destroy, GCP
  deploys and deletes, and `kubectl apply/delete` are denied, so you run those
  yourself.
