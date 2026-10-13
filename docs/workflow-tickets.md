# Ticket workflow

How a Jira ticket goes from start to merged when working with Claude in this
workspace. Claude follows this by default. The user can override any step
for a given ticket.

## Roles

| Who | Does |
|---|---|
| **Claude, automatically** | Creates branches, edits code, runs tests, commits, keeps ticket notes current, watches CI |
| **Claude, after asking** | `git push` (branches and tags), `gh pr create`, `gh pr ready` (un-draft), changes to `plan.md` |
| **The user only** | Creates the Jira ticket, picks reviewers, merges PRs |

`.claude/settings.json` enforces the boundaries. Push, PR creation,
un-drafting and raw `gh api` calls are in the `ask` list, so they always
prompt. `gh pr merge` is in `deny`, so Claude cannot merge.

Before asking to push or open a PR, Claude says what it is about to do:
repo, branch, commits being pushed, and a summary of the PR description. The
user can approve with full context.

## Branches

The same name is used everywhere: **`tickets/DM-NNNNN`**.

- In each affected submodule (`repos/<name>`), for the code.
- In this workspace, for the ticket's notes, doc updates, and submodule
  pointer bump.

Ticket code changes happen directly in the submodules (`repos/<name>`), not
in other checkouts.

## 1. Start

The user gives Claude a ticket number. The ticket already exists in Jira.

1. Check the active gcloud project is `ppdb-dev-5c07` (the session-start
   hook reports it).
2. In the workspace: `git switch -c tickets/DM-NNNNN` from up-to-date `main`.
3. Copy the template: `cp -r notes/tickets/_template notes/tickets/DM-NNNNN`.
4. Draft `plan.md` with the user: goal, approach, affected repos,
   cross-repo dependencies, open questions. Use `/rubinobs-jira DM-NNNNN`
   to pull the ticket, its epic, links and open sibling tickets as input.
5. In each affected submodule:

   ```bash
   git -C repos/<name> switch main && git -C repos/<name> pull
   git -C repos/<name> switch -c tickets/DM-NNNNN
   ```

6. Fill `todo.md` from the plan. Commit the notes on the workspace branch.

## 2. Work

- **Session start:** read `plan.md`, `todo.md` and `notes.md` for the ticket.
- **Ticket notes:**
  - Keep `todo.md` current: check items off and add new ones.
  - Append to `notes.md` at the end of each session or major step: what was
    done, findings, decisions, what's blocked.
  - Ask before changing `plan.md`.
  - Commit note updates to the workspace ticket branch as work proceeds.
- **Build and test:** use the `ppdb_env` conda env.
  - Rebuild with `pip install --no-deps .` (dax_ppdb, sdm_schemas) before testing.
  - Anything touching GCP runs only in **dev** (`ppdb-dev-5c07`), never int.
- **Commits:** small and focused, with an imperative summary line. The ticket
  number is in the branch name, not the commit message.
- **Scripts and artifacts:** one-off scripts go in `ppdb-scripts` (separate
  repo), not here. Reusable code goes in the relevant component repo.

## 3. Cross-repo changes

Use the plan's "Cross-repo dependencies" section and the checklist in
[architecture.md](architecture.md#cross-repo-change-checklist). Common cases:

- **dax_ppdb change needed by the cloud functions:** merge in dax_ppdb, tag
  `cloudrun-vX.Y.Z` (push the tag only after asking), then bump the
  `lsst-dax-ppdb @ ...@cloudrun-vX.Y.Z` pin in every
  `ppdb-cloud-functions/*/requirements*.txt`.
- **New env var, topic, bucket or permission for a function:** a matching
  change in `idf_deploy/environment/deployments/ppdb/services/`. Remember
  that apply only triggers on a tfvars change.
- **Schema change:** `sdm_schemas` → dax_ppdb → BigQuery tables → TAP_SCHEMA
  → ppdbtap mappings.

List related PRs in each PR description so reviewers see the whole change.

## 4. Push and open PRs

For each repo with changes, after asking:

```bash
cd repos/<name>
git push -u origin tickets/DM-NNNNN
gh pr create --draft --base main --head tickets/DM-NNNNN \
  --title "DM-NNNNN: <Jira summary>" --body-file <file>
```

Run `git push` from inside the repo, not as `git -C <dir> push`. The
permission rules match on how a command starts, and this keeps the "ask"
prompt reliable. Write the PR body file in the session scratchpad, not in
the repo.

PR description:

```markdown
## Summary
<What changed and why, in a few sentences.>

## Changes
- <Main changes, one line each.>

## Testing
<How it was tested: unit tests, dev runs, commands.>

## Related
- Jira: https://rubinobs.atlassian.net/browse/DM-NNNNN
- <Links to related PRs in other repos.>
```

Repo-specific cautions to mention when asking:

- **ppdb-cloud-functions:** opening or updating a PR **deploys that function
  to dev**.
- **phalanx, idf_deploy:** upstream repos owned by other teams (SQuaRE, IT),
  with their own reviewers and CODEOWNERS.

## 5. CI

- Watch: `gh pr checks <pr> --repo <owner>/<name> --watch`.
- Report the result in chat and in `notes.md`.
- **On failure:** report which check failed and the relevant log lines
  (`gh run view <run-id> --log-failed`). **Don't fix automatically.** Wait
  for the user to say what to do.
- **On success:** say so and ask whether to un-draft (`gh pr ready`). The user
  may prefer to do it while picking reviewers.

## 6. Review and merge

- The user requests reviewers and merges. **Claude never merges.**
- Claude helps address review comments when asked:
  `gh pr view <pr> --comments`, edit, commit, then ask before pushing.

## 7. Close-out

After the user has merged the code PRs and says the ticket is done:

1. In each affected submodule: `switch main`, `pull`, and delete the local
   ticket branch (`git branch -d tickets/DM-NNNNN`).
2. In `plan.md`, set `Status: merged`. Add a final `notes.md` entry: what
   shipped, PR links, follow-ups.
3. Move anything durable learned during the ticket into `docs/` or
   `.claude/rules/`.
4. Stage the submodule pointer bumps (`git add repos/<name>`) and commit
   everything on the workspace ticket branch.
5. Ask, then push the workspace branch and open its PR (non-draft is fine;
   it's docs). The user merges it.
6. Switch the workspace back to `main` and pull.

## Not automated (yet)

- Creating Jira tickets, commenting, or changing their status. `/rubinobs-jira`
  is read-only, and Jira write tools are denied in `.claude/settings.json`.
- Requesting reviewers.
