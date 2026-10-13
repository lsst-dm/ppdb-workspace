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

## Repository layout

```
ppdb-workspace/
├── README.md                 # this file
├── CLAUDE.md                 # shared Claude context, loaded every session
├── CLAUDE.local.md           # personal Claude context (gitignored, optional)
├── ppdb.code-workspace       # VS Code multi-root workspace
├── .gitmodules               # submodule URLs and tracked branches
├── .claude/
│   ├── settings.json         # permissions and hooks for Claude Code
│   ├── hooks/
│   │   └── session-start.sh  # runs at the start of each Claude session
│   └── rules/                # per-component guidance, loaded by path
│       ├── dax-ppdb.md
│       ├── cloud-functions.md
│       ├── idf-deploy.md
│       ├── phalanx.md
│       └── sdm-schemas.md
├── docs/
│   ├── architecture.md       # system overview across all repos
│   ├── glossary.md           # PPDB terms
│   └── components/           # detailed reference, one file per submodule
├── notes/
│   └── tickets/              # working notes per Jira ticket
│       └── _template.md
└── repos/                    # git submodules (the actual code)
    ├── dax_ppdb/
    ├── ppdb-cloud-functions/
    ├── idf_deploy/
    ├── phalanx/
    └── sdm_schemas/
```

| Path | What it contains | Purpose |
|---|---|---|
| `README.md` | Setup, layout, submodule workflow | Orientation for people |
| `CLAUDE.md` | Component map, short data flow, docs index, conventions, conda envs, GCP projects (dev for tests, never int) | The context Claude always has. Keep it short; put details in `docs/` or `.claude/rules/` |
| `CLAUDE.local.md` | Whatever you want: personal preferences, local paths | Personal Claude context that isn't shared. Gitignored |
| `ppdb.code-workspace` | Workspace root plus each submodule as a folder | Open in VS Code for a multi-root view |
| `.gitmodules` | URL and branch (`main`) for each submodule; `idf_deploy` and `phalanx` are shallow | Defines what `repos/` contains |
| `.claude/settings.json` | `permissions.allow`: read-only commands Claude may run without asking. `permissions.deny`: commands Claude may never run (push, `terraform apply`, GCP deploys and deletes, `kubectl apply/delete`). `hooks`: registers the session-start hook | Guardrails and fewer permission prompts. Commands on neither list prompt you |
| `.claude/hooks/session-start.sh` | Bash script that checks `gcloud config get-value project` and runs `git status` in each submodule | Warns you if the active project isn't `ppdb-dev-5c07`, and gives Claude the current branch and dirty state of each repo |
| `.claude/rules/*.md` | Layout, build and test commands, deploy behavior, and gotchas for one component. Each has a `paths:` header such as `repos/dax_ppdb/**` | Claude loads a rule file only when working on files under its path, so component detail doesn't crowd every session |
| `docs/architecture.md` | Pipeline diagram (APDB → GCS → BigQuery → TAP), chunk lifecycle, BigQuery datasets, which repo owns what, cross-repo change checklist | The system-level picture no single repo provides. Read before cross-repo work |
| `docs/glossary.md` | APDB, PPDB, replica chunk, datasets, facilities, environments | Shared vocabulary |
| `docs/components/*.md` | Detailed reference per submodule: configs, env vars, message formats, Terraform resources, Helm values. For idf_deploy, phalanx and sdm_schemas, only the PPDB parts | Read on demand. Each records the commit it was written from, so you can tell when it may be stale |
| `notes/tickets/` | One `DM-NNNNN.md` per active ticket, copied from `_template.md`: goal, repos and branches, decisions, next steps, session log | Carries working state between Claude sessions. Delete or archive when the ticket is done |
| `repos/` | The component repositories as git submodules | Where code changes happen. Each has its own branches, PRs and CI |

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

## How Claude uses this context

| When | What Claude sees |
|---|---|
| Every session | `CLAUDE.md`, `CLAUDE.local.md`, and the session-start hook output |
| Working on files under a submodule | The matching `.claude/rules/*.md` |
| On demand | `docs/` and `notes/tickets/`, read when relevant or when asked |

Put new knowledge at the narrowest level that fits:
- Component gotchas go in `.claude/rules/`.
- Ticket state goes in `notes/tickets/`.
- Durable system facts go in `docs/`.
- Only workspace-wide essentials go in `CLAUDE.md`.
