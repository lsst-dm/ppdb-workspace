#!/usr/bin/env bash
# SessionStart hook: check the active GCP project and summarize submodule state.
# Emits JSON: a user-visible warning (systemMessage) if the project is not dev,
# and a short status block added to Claude's context (additionalContext).

DEV_PROJECT="ppdb-dev-5c07"
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

project=$(gcloud config get-value project 2>/dev/null)
project=${project:-<unset>}

warning=""
if [[ "$project" != "$DEV_PROJECT" ]]; then
    warning="WARNING: active gcloud project is '$project', not $DEV_PROJECT (dev). Do not run tests or GCP commands until this is resolved."
fi

status="Active gcloud project: $project"
[[ -n "$warning" ]] && status+=" (NOT dev; ask the user before any GCP command)"
status+=$'\nSubmodules:'
while read -r path; do
    dir="$ROOT/$path"
    if [[ ! -e "$dir/.git" ]]; then
        status+=$'\n'"  $path: not initialized"
        continue
    fi
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD || echo "detached@$(git -C "$dir" rev-parse --short HEAD)")
    dirty=$(git -C "$dir" status --porcelain | wc -l)
    state="clean"
    (( dirty > 0 )) && state="$dirty changed"
    status+=$'\n'"  $path: $branch, $state"
done < <(git -C "$ROOT" config -f .gitmodules --get-regexp '\.path$' | awk '{print $2}')

jq -n --arg warn "$warning" --arg ctx "$status" '
  {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}
  + (if $warn != "" then {systemMessage: $warn} else {} end)'
