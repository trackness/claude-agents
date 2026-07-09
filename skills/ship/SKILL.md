---
name: ship
description: Land the current feature branch on main. Use when work on a branch is complete and ready to ship.
disable-model-invocation: true
---

# Ship Current Changes

Automatically commit, PR, review, and merge the current branch.

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`
- `github.project.number`, `github.project.nodeId`
- `github.project.fields.status.id` and all status option IDs
- `testCommand`

## Workflow

1. **Check current state:**
   - **Detect default branch:** Run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`. If that fails, run `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`. Store the result as `DEFAULT_BRANCH`.
   - **HARD GATE:** If on the default branch, STOP. Check whether bad commits exist on the default branch (commits that should be on a feature branch). If so, warn the user and present the situation: which commits are on the default branch, whether they've been pushed, and what the options are (`git reset --hard` + `git push --force-with-lease` for unpushed, or revert for pushed). **Do not execute any destructive operation without explicit user confirmation.** Once resolved, create a feature branch before doing anything else. No commits to the default branch — ever.
   - If uncommitted changes exist, create a commit with an appropriate message based on the changes

2. **Run tests:**
   - Run the test command from `project.json` (`testCommand`)
   - If any tests fail: read and follow `${CLAUDE_PLUGIN_ROOT}/shared/references/debugging.md` before attempting any fix, then amend or reset the commit from step 1 before re-running `/ship`
   - If all tests pass: proceed

3. **Documentation gate:**
   - **HARD GATE:** Check whether the branch changes the tech stack, adds/removes dependencies, changes file structure, deletes/renames files, or otherwise invalidates existing documentation. If so, update any affected docs that exist in this repo (CLAUDE.md, README, ADRs, issue templates, workflow docs) before proceeding. Stale docs do not ship.

4. **Push and PR:**
   - Push the current branch to remote
   - Create a pull request with auto-generated title and description based on commits and changes
   - Merge strategy: `gh pr merge --squash --delete-branch` (squash keeps main history clean, `--delete-branch` cleans up)
   - `/ship` itself does not detect issue numbers. When invoked via `/task`, the `closes #<n>` line is injected into the PR body by the `/task` workflow — `/ship` passes the description through unchanged. For standalone `/ship` invocations, add `closes #<n>` manually to the PR description if needed.

5. **Review:**
   - Launch the `pr-reviewer` agent using `subagent_type: "gh-pm:pr-reviewer"` with `isolation: "worktree"` (prevents the reviewer's git operations from modifying the working tree)
   - The agent will check architecture, security, performance, error handling, testing, and readability
   - Wait for the agent's assessment: APPROVE, APPROVE WITH COMMENTS, REQUEST CHANGES, or REJECT
   - **CRITICAL:** The ONLY reviewer that satisfies this gate is `subagent_type: "gh-pm:pr-reviewer"`. Do NOT dispatch any other review agent, and do NOT substitute or supplement it with any general-purpose code-review skill. No other reviewer's verdict clears the merge gate.

6. **Respond to the review:**

   Findings are claims to evaluate, not orders to obey. Never agree performatively; never implement a finding you have not verified against the actual code. Work through the findings one at a time — restate, evaluate, then fix or adjudicate or clarify each before touching the next, and re-verify after each.

   For every finding:
   - **Restate** it in your own words, then read the actual code it refers to. If the finding is ambiguous, ask for clarification BEFORE implementing anything — never guess at what the reviewer meant.
   - **Evaluate** it against these five questions:
     1. Is it technically correct for THIS codebase?
     2. Would the change break existing functionality?
     3. Is there a reason for the current implementation the reviewer may have missed?
     4. Does the claim hold on every platform and version this code targets?
     5. Does the reviewer have full context, or is the finding based on a partial view of the code?
   - **YAGNI / dead-code check:** before implementing any finding that asks you to add handling, abstraction, or defensive machinery, grep for the actual callers first. If the path is unused, propose removing it instead of building what the finding requested — do not gold-plate code no one calls.
   - **Correct finding** → fix it, one at a time, then report exactly what you changed.
   - **Wrong, YAGNI, or wrong-for-this-stack** → push back. Post the reasoning as a PR comment and record an adjudication entry. Do NOT silently implement it, and do NOT silently drop it.

   **Adjudication log.** A finding rejected with reasoning counts as addressed — the loop does not require obeying it. Each entry states exactly three things: the finding, the decision, and the evidence. No agreement language — no "good catch", no hedging, no apology — just finding + decision + evidence. Keep the running log for this branch.

   **After processing all findings:** commit the fixes, run tests (**go back to step 2** on any failure), push, then re-dispatch the reviewer (**go back to step 5**). The re-review dispatch prompt MUST include the adjudication log, so the reviewer sees which findings were rejected and why.

   - If the reviewer re-flags a finding already in the adjudication log, do NOT loop on it — escalate to the human with both the finding and your adjudication, and stop.
   - Keep iterating fix/adjudicate → test → push → review until the reviewer returns an APPROVE with every finding either fixed or adjudicated.

   **MERGE GATE:** Before executing `gh pr merge`, verify: (1) the most recent pr-reviewer dispatch returned APPROVE, and (2) every finding it raised is either fixed or carries an adjudication entry. If any finding is neither fixed nor adjudicated, do not merge — loop back to fix and re-review. This gate is non-negotiable and cannot be skipped regardless of how trivial a finding appears.

7. **Post-merge: set Project Status to Done:**
   - If the PR body contains `closes #<n>`, extract the issue number(s) and set their Project Status to Done:
     ```bash
     ITEM_ID=$(gh project item-list <project.number> --owner <owner> --limit 200 --format json | jq -r '.items[] | select(.content.number == <n>) | .id')
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.status.id> --single-select-option-id <fields.status.options.done>
     ```
   - This ensures the Project board stays in sync with issue state without relying on manual post-merge steps

## Notes

- Auto-generates commit messages by analyzing the diff
- Auto-generates PR descriptions based on commit history
- Uses the pr-reviewer agent for comprehensive autonomous review
- Ensures branch is deleted after successful merge
- Returns to the default branch after merge completes
- **IMPORTANT:** Never add Claude Code attribution to commits, PRs, or any code
