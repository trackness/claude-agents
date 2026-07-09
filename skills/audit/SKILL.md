---
name: audit
description: Thoroughly review the codebase against 11 dimensions and generate suggested GitHub Issues. Use for periodic codebase health checks.
disable-model-invocation: true
---

# Audit Repository

Thoroughly review the codebase and generate suggested new tasks.

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`
- `github.project.number`, `github.project.nodeId`
- All field IDs and option IDs from `github.project.fields`
- `labels` list

## Workflow

1. **Read current state:**
   - Read CLAUDE.md — understand what the project does and its tech stack
   - Fetch all project items: `gh project item-list <project.number> --owner <owner> --limit 200 --format json` — note all items across all statuses (Ready, In Progress, Done, Won't Do, Backlog)
   - Fetch all open GitHub issues: `gh issue list --state open --limit 200 --json number,title,labels` — these are already tracked; do not duplicate them
   - Glob the entire repository for source files — read everything relevant (source, tests, config, Dockerfiles, package.json files, migrations, docs, etc.)
   - If the user specifies a scope (e.g., a specific dimension, directory, or concern), focus the audit on that scope rather than all 11 dimensions across the entire codebase

2. **Identify gaps across all dimensions:**
   - `#security` — unvalidated inputs, missing headers, exposed secrets, OWASP Top 10
   - `#testing` — untested code paths, missing edge cases, low coverage areas
   - `#reliability` — unhandled errors, missing timeouts, data integrity risks
   - `#ux` — poor interactions, missing feedback, confusing flows
   - `#accessibility` — ARIA gaps, keyboard traps, contrast issues
   - `#devops` — missing automation, fragile deployment steps
   - `#documentation` — undocumented behaviour, stale docs
   - `#performance` — unnecessary work, missing caching, slow paths
   - `#architecture` — structural concerns, design patterns, significant refactoring opportunities, repo arrangement/layout
   - `#feature` — missing user-facing capabilities with clear value
   - `#production` — rate limiting, graceful shutdown, error reporting, observability

3. **Cross-reference:**
   - Do not suggest tasks already open in GitHub Issues
   - Do not suggest tasks closed with Won't Do status in Projects
   - Check Backlog and Ready issues in the project for overlap — suggest promoting Backlog items rather than duplicating

4. **Draft output:**
   - For each finding, recommend a status:
     - **Ready** — well-understood, concrete findings with clear implementation path. Draft using the issue body template at `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md`.
     - **Backlog** — speculative or broad findings that need more research before implementation. Draft with sufficient context for a future `/promote` invocation (idea, motivation, known constraints).
   - Present all suggestions to the developer for review before creating anything

   **Do not soft-pedal findings.** If something is a structural problem, a gap, or a smell — raise it as an issue. Phrases like "acceptable at this scale", "minor", "fine for now", or "not worth it given the project size" are forbidden. Every finding warrants an issue — if it does not, it should not appear in the audit at all.

5. **On user approval (per item):**
   - **Ready findings:**
     ```bash
     ISSUE_URL=$(gh issue create --title "..." --body "..." --label "label1,label2")
     ITEM_ID=$(gh project item-add <project.number> --owner <owner> --url "$ISSUE_URL" --format json | jq -r '.id')
     # Status = Ready
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.status.id> --single-select-option-id <fields.status.options.ready>
     # Priority
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.priority.id> --single-select-option-id <priority-option-id>
     # Effort
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.effort.id> --single-select-option-id <effort-option-id>
     # Type
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.type.id> --single-select-option-id <type-option-id>
     ```
     Set dependencies via the mutation at `${CLAUDE_PLUGIN_ROOT}/shared/queries/add-blocked-by.graphql` if applicable.

   - **Backlog findings:**
     ```bash
     ISSUE_URL=$(gh issue create --title "..." --body "..." --label "label1,label2")
     ITEM_ID=$(gh project item-add <project.number> --owner <owner> --url "$ISSUE_URL" --format json | jq -r '.id')
     # Status = Backlog
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.status.id> --single-select-option-id <fields.status.options.backlog>
     ```
     No Priority, Effort, or Type — these are determined during `/promote`. Set dependencies via `${CLAUDE_PLUGIN_ROOT}/shared/queries/add-blocked-by.graphql` if known.

## Notes

- Audit is pure API calls — no file changes, no branch, no commit needed
- The 11-dimension gap analysis is exhaustive — do not skip dimensions
- Per-item user approval is required before creating any issue
