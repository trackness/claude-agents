---
name: task
description: Use when starting or resuming work on a project-board issue, or to pull and work the next Ready item off the queue.
disable-model-invocation: true
argument-hint: "[issue-number ...]"
---

# Complete Task by Issue Number

Implement a task from GitHub Issues and ship it using the /ship workflow.

## Usage

```text
/task [issue-number ...]
```

Examples: `/task` (pull the next Ready item), `/task 15`, `/task 47 49` (batch).

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`, `github.repositoryNodeId`
- `github.project.number`, `github.project.nodeId`
- All field IDs and option IDs from `github.project.fields`

## Workflow

1. **Select the issue(s) to work:**
   - **Arguments given** → work those issue numbers in the order supplied. Multiple numbers are a **batch**: run the entire cycle (locate → claim → branch → implement → ship) to completion for the first number, then repeat it from the top for the next, and so on. Batches are sequential full cycles — never interleave two issues on one branch, and never start the second before the first has shipped.
   - **No argument** → pull the top item off the **Ready** queue using the queue-ordering rule defined in `/status` (its canonical home — do not restate the rule here, and do not order the queue by any other criteria). Announce which issue you selected and why before doing anything else.

2. **Locate on the board and detect a resume:**
   - Fetch project data: `gh project item-list <project.number> --owner <owner> --limit 200 --format json` — locate by `content.number`.
   - If not found: the issue exists in GitHub but is not on the project board. Prompt "Issue #<n> is not on the project board. Add it? (y/n)". If yes, add it and configure it, then proceed. If no, exit.
   - Run the combined GraphQL query from `${CLAUDE_SKILL_DIR}/queries/combined-issue-query.graphql` to get dependencies, sub-issue siblings, and linked branches in one call. Substitute owner, repo, and issue number.
   - **Resume path:** If the item's Status is already **In Progress** and it has a **linked branch**, this is in-flight work. Do NOT re-branch and do NOT re-claim. Fetch and check out the linked branch, then assess where it stands — `git log`, `git diff <base>...HEAD`, and run the test command from project.json — and continue from there. Skip the claim (step 5) and branch creation (step 6) and resume at Implement (step 8).
   - **In Progress with no linked branch:** ambiguous — either a concurrent session holds it or it is a stuck claim. Stop and ask the user whether to adopt it (check out or create a branch and continue) or leave it alone. Do not silently start a second branch on it.
   - **Sub-issue sibling check:** If the issue has a `parent` with sibling `subIssues`, check whether any siblings are also Ready and should be co-implemented on one shared branch. Prompt the user with the sibling list before deciding.

3. **Fetch full spec:**
   - `gh issue view <n>` to fetch Why, Implementation, Files, Testing, Acceptance Criteria
   - Read Effort from the project data fetched in step 2. If Effort is unset (null), treat as Low.

4. **Check dependencies:**
   - Use the `blockedBy` field from the combined GraphQL query in step 2
   - `state: CLOSED`, `stateReason: COMPLETED` → satisfied
   - `state: CLOSED`, `stateReason: NOT_PLANNED` → warn developer, continue
   - `state: CLOSED`, `stateReason: DUPLICATE` → the blocker was closed as a duplicate; the actual work lives in its canonical issue, not here. Find the canonical issue (named in the duplicate's close event or its comments) and confirm that one is CLOSED/COMPLETED. Only then treat the dependency as satisfied — if the canonical is still open, warn and stop exactly as for an open blocker.
   - `state: OPEN` → warn and stop; implement prerequisite first
   - **Any other combination** (an unexpected or null `stateReason`, or anything not matched above) → do NOT assume the dependency is satisfied. Warn the developer, surface the raw state/stateReason, and stop until the prerequisite is confirmed resolved.

5. **Claim the issue (concurrency guard):**
   - Set the item's Status to **In Progress** before branch creation and before any implementation work. On the **no-argument queue-pop path** this claim is the first board write for the item, and claiming it immediately is the concurrency guard — two sessions reading the Ready queue would otherwise both pick the same top item and double-grab it, so the claim must land before anything else. (On the argument path there is no queue contention, and if step 2 added the issue to the board that add already wrote to the board ahead of this claim — the strict "claim first" ordering carries weight only for the queue-pop case, where it prevents the double-grab.)
     ```bash
     ITEM_ID=$(gh project item-list <project.number> --owner <owner> --limit 200 --format json | jq -r '.items[] | select(.content.number == <n>) | .id')
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.status.id> --single-select-option-id <fields.status.options.inProgress>
     ```
   - Skip this step when resuming (the item is already In Progress).

6. **Create the feature branch and link it:**
   - Use branch naming convention: `<type>/<short-description>`
   - For combined sibling implementations, use a name reflecting the shared theme
   - Link the branch to the issue for early visibility using the mutation from `${CLAUDE_SKILL_DIR}/queries/create-linked-branch.graphql`. Substitute issue node ID, branch name, commit SHA, and repository node ID from project.json.
   - **Worktree / branch hygiene** — if you isolate the work in a git worktree: prefer the harness's native isolation over a manual `git worktree`. Before creating any worktree directory, confirm it is gitignored with `git check-ignore <dir>` — never create a worktree in a tracked path. Never delete a branch before removing its worktree; never run the removal from inside the worktree; and never clean up a worktree you did not create.

7. **Decompose (Medium, High, or Highest Effort only):**
   - **Do NOT decompose Trivial or Low effort issues** — the issue body's Implementation section is sufficient for those.
   - This skill owns its control flow — do not invoke external planning/brainstorming skills within it. Produce the decomposition inline, hold it in context, and work from it. NO plan file on disk — the issue body is the only artifact.
   - Break the work into an ordered list of independently-testable tasks. For each task, capture: the file(s) it touches and its single responsibility; the failing test that opens it and the verify command with its expected output; the interfaces it consumes and produces.
   - **Task Right-Sizing:** a task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate; split only where a reviewer could reject one task while approving its neighbor.
   - **Interfaces — Consumes / Produces:** each sub-task names the exact signatures it uses from and provides to neighbors, so the tasks compose without rework.
   - **No Placeholders.** These are plan failures — a decomposition containing any of them is not done: "TBD", "add appropriate error handling", "similar to task N", or any step that describes without showing.
   - Reconcile the decomposition against the issue's Implementation and Files sections; flag any drift to the developer before proceeding.

8. **Implement using TDD:**
   - Read and follow `${CLAUDE_PLUGIN_ROOT}/shared/references/tdd.md`.
   - **Treat Implementation and Files sections as guidance** — inspect actual current code state first; flag significant drift to the developer before proceeding

9. **Verify before marking complete:**
   - Read and follow `${CLAUDE_PLUGIN_ROOT}/shared/references/verification.md`.
   - Use Acceptance Criteria as the definition of done, in conjunction with the verification reference

10. **Documentation check:**
    - Review what this task changed: new dependencies, deleted/renamed files, tech stack changes, workflow changes.
    - Check any project documentation that exists in this repo (CLAUDE.md, README, ADRs, workflow docs) for anything invalidated by these changes. Update now, on this branch, before shipping.

11. **Ship it:**
    - Use the /ship workflow
    - `/task` is responsible for including `closes #<n>` in the PR body for each issue being shipped — either pass it to `/ship` as part of the description, or add it afterward with `gh pr edit`. GitHub auto-closes issues on merge.
    - `/ship` handles setting Project Status to Done post-merge — do NOT duplicate that here.
    - **Batch:** after this issue ships, return to step 2 for the next number in the batch. Do not begin it before this one has shipped.

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

### Stuck-state rule

- If you abandon the work, hit a blocker, or the session ends before `/ship` completes, **reset the item's Status from In Progress back to Ready** and leave an issue comment stating the branch name, what is done so far, and what remains. Never leave an item wedged at In Progress with no live work behind it — a stale claim blocks the queue and misleads `/status`.
- **When to declare stuck rather than force through** — stop, apply the reset above, and surface the situation to the user when any of these holds:
  - a genuine blocker is hit (a dependency, access, or environment problem you cannot resolve),
  - the issue spec has critical gaps (Acceptance Criteria or Implementation missing the detail needed to proceed),
  - an instruction is unclear and guessing would risk building the wrong thing, or
  - verification fails repeatedly with no converging fix.
- Do not thrash: forcing through a stuck state produces worse work than stopping cleanly and handing it back.
