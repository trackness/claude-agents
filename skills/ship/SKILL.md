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
- `ship.autoMerge` (defaults to `true` when the key or the `ship` block is absent — see step 8)

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
   - `/ship` itself does not detect issue numbers. When invoked via `/task`, the `closes #<n>` line is injected into the PR body by the `/task` workflow — `/ship` passes the description through unchanged. For standalone `/ship` invocations, add `closes #<n>` manually to the PR description if needed.

5. **Review:**
   - Launch the `pr-reviewer` agent using `subagent_type: "gh-pm:pr-reviewer"` with `isolation: "worktree"` (prevents the reviewer's git operations from modifying the working tree)
   - The agent will check architecture, security, performance, error handling, testing, and readability
   - Wait for the agent's assessment — one of three verdicts: **APPROVE** (no findings above NITPICK), **REQUEST CHANGES**, or **REJECT**. There is no "approve with comments": a verdict that carried anything above NITPICK is REQUEST CHANGES, not an approval.
   - **APPROVE = merge-eligible.** APPROVE means no findings above NITPICK remain; it satisfies this gate. Any NITPICK-level notes the reviewer attached do not block the merge — surface them in the PR summary (see steps 8 and 9) so they are recorded, not silently dropped.
   - **CRITICAL:** The ONLY reviewer that satisfies this gate is `subagent_type: "gh-pm:pr-reviewer"`. Do NOT dispatch any other review agent, and do NOT substitute or supplement it with any general-purpose code-review skill. No other reviewer's verdict clears the merge gate.
   - **Worktree hygiene:** Prefer the harness's native `isolation: "worktree"` (used here) over any manual `git worktree` — the harness creates the reviewer's worktree and reclaims it for you. If you ever fall back to a manual worktree: confirm its directory is ignored with `git check-ignore <dir>` before creating it; never delete the feature branch while a worktree still occupies it (remove the worktree first); never run the removal from inside that worktree; and never remove a worktree you did not create.

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

   **REVIEW GATE:** The review is clean only when the most recent pr-reviewer dispatch returned APPROVE AND every finding it raised is either fixed or carries an adjudication entry. Until both hold, do not advance — loop back to fix and re-review. This gate is non-negotiable and cannot be skipped regardless of how trivial a finding appears. A clean review is a precondition for merge, not permission to merge: the CI gate (step 7) and the auto-merge decision (step 8) still stand between here and `gh pr merge`.

7. **CI gate:**

   The branch and PR are pushed and CI runs against the latest commit. Before any merge decision, the PR's checks MUST be green. A clean pr-reviewer verdict does not substitute for green CI — the reviewer reads the diff, CI runs the code.

   - Run `gh pr checks --watch --fail-fast` for the current PR (no argument selects the PR of the current branch). `--watch` blocks until every check reaches a terminal state, so it absorbs the pending case for you.
   - **Pending** — never proceed on a pending state. `--watch` already waits; if you are polling by hand instead, re-poll until the checks finish (`gh pr checks` exits `8` while any check is still pending).
   - **All checks pass** (exit `0`) — the gate is satisfied; proceed to step 8.
   - **Any check fails** (non-zero exit other than pending) — treat each failing check exactly like a review finding. Read the failing job's log, then **go back to step 2**: read `${CLAUDE_PLUGIN_ROOT}/shared/references/debugging.md`, fix the cause, commit, and let the fix flow back through tests, push, and re-review before returning here. Never merge over a red check.
   - **No checks configured** — if gh reports no checks on the branch (a repo with no CI), the gate is vacuously satisfied; proceed.

8. **Auto-merge decision (`ship.autoMerge`):**

   Read `ship.autoMerge` from `.claude/project.json`.

   - **`false`** — STOP here. The work is complete and the PR is ready, but the merge is the user's call. Report: the PR URL, the review outcome (APPROVE, plus any nitpicks surfaced in the review summary), the CI result (all checks green), and the adjudication log. Then wait. Merge ONLY on the user's explicit instruction to merge — approval of the PR, the code, the approach, or the plan is NOT that instruction. When the user says to merge, continue to step 9.
   - **`true`, key absent, or no `ship` block** — proceed to step 9 and merge. A missing key defaults to `true`, so project.json files written before this key existed keep the original auto-merge behavior (backward compatible).

   The `enforce-merge-gate` hook is the mechanical backstop for the `false` case — it turns `gh pr merge` into an `ask`. That hook is a safety net, not the logic: this skill must reach the correct outcome on its own whether or not the hook fires.

9. **Merge:**

   **MERGE GATE — non-negotiable.** Before running `gh pr merge`, confirm all three hold: (1) the most recent pr-reviewer dispatch returned APPROVE; (2) every finding it raised is fixed or carries an adjudication entry; (3) the CI gate passed (all checks green). If any of the three is unmet, do not merge — loop back to the step that clears it. No finding is too trivial to skip this gate.

   - If the APPROVE carried any NITPICK-level notes, record them in the PR summary/body before merging (`gh pr edit --body`) so they survive in the merged history rather than vanishing with the review.
   - Merge with `gh pr merge --squash --delete-branch` (squash keeps the default branch history clean; `--delete-branch` removes the merged branch).
   - Return to the default branch after the merge completes.

10. **Post-merge: set Project Status to Done:**
   - If the PR body contains `closes #<n>`, extract the issue number(s) and set their Project Status to Done:
     ```bash
     ITEM_ID=$(gh project item-list <project.number> --owner <owner> --limit 200 --format json | jq -r '.items[] | select(.content.number == <n>) | .id')
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.status.id> --single-select-option-id <fields.status.options.done>
     ```
   - This ensures the Project board stays in sync with issue state without relying on manual post-merge steps

11. **Sub-issue roll-up:**

   For each issue this run set to Done, check whether it has a parent and whether that parent's other sub-issues are now all closed. The combined-issue query already returns exactly this shape — the issue's `parent` plus that parent's `subIssues` with their `state` — so run `${CLAUDE_PLUGIN_ROOT}/skills/task/queries/combined-issue-query.graphql` for the Done issue's number (substitute owner, repo, number) rather than composing raw API calls.

   - **No `parent`** — nothing to roll up.
   - **Parent still has open `subIssues`** — leave the parent alone; it has live children.
   - **Every one of the parent's `subIssues` is closed** — post a comment on the parent (`gh issue comment <parentNumber>`) stating that all of its sub-issues are complete and it is ready for human review and closure. NEVER close the parent automatically — parent closure is always a human decision.

## Notes

- Auto-generates commit messages by analyzing the diff
- Auto-generates PR descriptions based on commit history
- Uses the pr-reviewer agent for comprehensive autonomous review
- Ensures branch is deleted after successful merge
- Returns to the default branch after merge completes
- **IMPORTANT:** Never add Claude Code attribution to commits, PRs, or any code
