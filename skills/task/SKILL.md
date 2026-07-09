---
name: task
description: Implement a tracked GitHub Issue from the project board. Use when starting work on an issue.
disable-model-invocation: true
argument-hint: "<issue-number> [issue-number ...]"
---

# Complete Task by Issue Number

Implement a task from GitHub Issues and ship it using the /ship workflow.

## Usage

```text
/task <issue-number> [issue-number ...]
```

Examples: `/task 15`, `/task 47 49`

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`, `github.repositoryNodeId`
- `github.project.number`, `github.project.nodeId`
- All field IDs and option IDs from `github.project.fields`

## Workflow

1. **Find the issue on the project board:**
   - Fetch project data: `gh project item-list <project.number> --owner <owner> --limit 200 --format json` — locate by `content.number`
   - If not found: the issue exists in GitHub but is not on the project board. Prompt "Issue #<n> is not on the project board. Add it? (y/n)". If yes, add it and configure it, then proceed. If no, exit.
   - Run the combined GraphQL query from `${CLAUDE_SKILL_DIR}/queries/combined-issue-query.graphql` to get dependencies, sub-issue siblings, and linked branches in one call. Substitute owner, repo, and issue number.
   - **Sub-issue sibling check:** If the issue has a `parent` with sibling `subIssues`, check whether any siblings are also Ready and should be co-implemented. Prompt the user with the sibling list.

2. **Fetch full spec:**
   - `gh issue view <n>` to fetch Why, Implementation, Files, Testing, Acceptance Criteria
   - Read Effort from the project data fetched in step 1. If Effort is unset (null), treat as Low.

3. **Check dependencies:**
   - Use the `blockedBy` field from the combined GraphQL query in step 1
   - `state: CLOSED`, `stateReason: COMPLETED` → satisfied
   - `state: CLOSED`, `stateReason: NOT_PLANNED` → warn developer, continue
   - `state: OPEN` → warn and stop; implement prerequisite first

4. **Create feature branch, set In Progress, and link branch:**
   - Use branch naming convention: `<type>/<short-description>`
   - For combined implementations, use a name reflecting the shared theme
   - Set each issue's project Status to In Progress:
     ```bash
     ITEM_ID=$(gh project item-list <project.number> --owner <owner> --limit 200 --format json | jq -r '.items[] | select(.content.number == <n>) | .id')
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.status.id> --single-select-option-id <fields.status.options.inProgress>
     ```
   - Link the branch to the issue for early visibility using the mutation from `${CLAUDE_SKILL_DIR}/queries/create-linked-branch.graphql`. Substitute issue node ID, branch name, commit SHA, and repository node ID from project.json.

5. **Decompose (Medium, High, or Highest Effort only):**
   - **Do NOT decompose Trivial or Low effort issues** — the issue body's Implementation section is sufficient for those.
   - This skill owns its control flow — do not invoke external planning/brainstorming skills within it. Produce the decomposition inline, hold it in context, and work from it. NO plan file on disk — the issue body is the only artifact.
   - Break the work into an ordered list of independently-testable tasks. For each task, capture: the file(s) it touches and its single responsibility; the failing test that opens it and the verify command with its expected output; the interfaces it consumes and produces.
   - **Task Right-Sizing:** a task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate; split only where a reviewer could reject one task while approving its neighbor.
   - **Interfaces — Consumes / Produces:** each sub-task names the exact signatures it uses from and provides to neighbors, so the tasks compose without rework.
   - **No Placeholders.** These are plan failures — a decomposition containing any of them is not done: "TBD", "add appropriate error handling", "similar to task N", or any step that describes without showing.
   - Reconcile the decomposition against the issue's Implementation and Files sections; flag any drift to the developer before proceeding.

6. **Implement using TDD:**
   - Read and follow `${CLAUDE_PLUGIN_ROOT}/shared/references/tdd.md`.
   - **Treat Implementation and Files sections as guidance** — inspect actual current code state first; flag significant drift to the developer before proceeding

7. **Verify before marking complete:**
   - Read and follow `${CLAUDE_PLUGIN_ROOT}/shared/references/verification.md`.
   - Use Acceptance Criteria as the definition of done, in conjunction with the verification reference

8. **Documentation check:**
   - Review what this task changed: new dependencies, deleted/renamed files, tech stack changes, workflow changes.
   - Check any project documentation that exists in this repo (CLAUDE.md, README, ADRs, workflow docs) for anything invalidated by these changes. Update now, on this branch, before shipping.

9. **Ship it:**
   - Use the /ship workflow
   - `/task` is responsible for including `closes #<n>` in the PR body for each issue being shipped — either pass it to `/ship` as part of the description, or add it afterward with `gh pr edit`. GitHub auto-closes issues on merge.
   - `/ship` step 8 handles setting Project Status to Done post-merge — do NOT duplicate that here.

## Error Handling

- **Issue not on project board:** Prompt to add it; exit only if developer declines
- **Issue already closed:** Warn and ask if they want to re-implement
- **Dependency open:** Warn and stop; implement the prerequisite first
- **Branch already exists:** Offer to switch to existing branch or create with different name

## Notes

- Never add Claude Code attribution to commits, PRs, or code
- Implementation/Files sections in issues may be stale — always verify against current code
- Issues are closed automatically when the PR merges via `closes #<n>` — do NOT close manually
- All project IDs come from `.claude/project.json` — never hardcode them
