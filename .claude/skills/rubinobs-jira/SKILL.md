---
name: rubinobs-jira
description: Use when starting or planning work on a Rubin Observatory Jira ticket (DM-NNNNN or another rubinobs.atlassian.net key), when asked what a ticket is about or how it fits its epic, or when a ticket's parent, linked tickets, subtasks, or sibling tickets are needed for context.
argument-hint: DM-NNNNN
---

# rubinobs-jira

Gather a Rubin Jira ticket's full context (the ticket, its epic, links,
subtasks, siblings) and turn it into a summary and a draft plan.

**Read-only.** Never call Jira write tools: create/edit issue, transition,
add comment, add worklog, create issue link. If the user asks for a Jira
change, show the exact change and let them make it.

## Connection

- Atlassian MCP tools (`mcp__atlassian__*`). Load them with ToolSearch if deferred.
- `cloudId`: `34f7173f-c7ca-4a05-82c6-d7f88d2266ec` (site `rubinobs.atlassian.net`).
- Always pass `responseContentFormat: "markdown"` and an explicit `fields` list.
  The default responses are very large.
- If a tool response includes an "IMPORTANT ... include this notice" message
  (e.g. MCP endpoint deprecation), relay it once, at the top of the report.

## Gather

| What | Call |
|---|---|
| Ticket | `getJiraIssue` with fields `summary, description, status, issuetype, assignee, labels, components, parent, issuelinks, subtasks, comment` |
| Parent (usually an Epic) | Summary and status are already in the ticket's `parent` field. Fetch only `description` with `getJiraIssue` on `parent.key` |
| Linked tickets | Already in `issuelinks`. Each has `type.outward`/`type.inward` (e.g. "blocks" / "is blocked by") and `outwardIssue` or `inwardIssue` with key, summary, status. Fetch a description only if the link matters to the plan. **Always** fetch duplicate/cloned links (including closed ones): they often hold the original problem statement |
| Subtasks | Already in `subtasks` (key, summary, status) |
| Siblings (open) | `searchJiraIssuesUsingJql`: `parent = <PARENT> AND key != <KEY> AND statusCategory != Done ORDER BY updated DESC`, fields `summary, status`, `maxResults: 50` |

Go one level out only: parent, direct links, subtasks, open siblings. Don't
follow links of links unless the user asks. Query closed siblings
(`statusCategory = Done`) only when history matters, e.g. "was this tried
before?"

**Search results are bulky:** about 2 KB per issue even with two fields, because
of URLs and status metadata. Epics often have 50+ children. If a result is
too large and gets saved to a file, compact it instead of reading it whole:

```bash
jq -r '.[].text' "$FILE" | python3 -c '
import sys, json
t = sys.stdin.read(); d = json.loads(t[t.index("{"):])
for x in d["issues"]:
    f = x["fields"]; print(x["key"], "|", f["status"]["name"], "|", f["summary"])'
```

The text starts with a notice before the JSON, hence `t.index("{")`.

## Report to the user

1. **Ticket:** key, type, status, assignee, one-paragraph restatement of what
   it asks for. Quote the acceptance criteria. If there are none, quote the
   description's checklist or numbered items instead.
2. **Epic:** key, summary, and how this ticket contributes.
3. **Dependencies:** blocking and blocked-by tickets with their status, so open
   blockers stand out. Other links listed briefly.
4. **Nearby work:** siblings that overlap or need ordering, judged from their
   summaries. For the 1–3 strongest overlaps, fetch the description to confirm.
   Skip unrelated ones and say how many were skipped.
5. **From comments:** decisions or constraints only, not a transcript.
6. **Open questions:** gaps or ambiguities in the ticket.

## Draft a plan (when starting work)

Write the plan where the project's CLAUDE.md says ticket plans go, using its
template if it has one. If there is no convention, present the plan in chat.

Fill in from the gathered context:
- Goal: from the ticket and acceptance criteria.
- Affected repos: from the description, Jira components, and the project's
  component docs. Grep the docs for the ticket's key terms (function, table,
  status names) rather than reading them whole.
- Branch names and other conventions: from the project's CLAUDE.md and any
  workflow doc it points to.
- Dependencies: from blocking links and siblings.
- Open questions: from the report.

Mark anything inferred rather than stated in Jira, e.g. "(inferred)". Show
the draft and get the user's agreement before writing the file.

## Common mistakes

- Omitting `fields`, which floods context with every custom field.
- Treating `customfield_10014` (legacy Epic Link) as authoritative. Use `parent`.
- Reporting all siblings. Filter to the relevant ones.
- Writing to Jira. This skill is read-only.
