---
name: status
description: Use when the user asks what to work on next, wants the state of the project board, or asks whether anything is stalled or untracked.
---

# Project Board Status

Read-only observability for the project board: what is Ready and in what order, what is In Progress (and whether any of it is wedged), what is untracked, and what to do next.

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`
- `github.project.number`, `github.project.nodeId`
- All field IDs and option IDs from `github.project.fields`

## Contract: zero writes

Status is **read-only**. It runs no `gh issue create`, no `gh issue edit`, no `gh project item-add`, no `gh project item-edit`, no branch, no commit, no file write — none. If a fix is warranted, status names it and points at the skill that performs it (`/task`, `/promote`, `/capture`); status itself changes nothing. Reporting a stale board while having quietly edited it is the one failure this skill exists to avoid.

## Queue-ordering rule (canonical — /task cites this)

The **Ready** queue is ordered by:

1. **Priority, descending** — Critical → High → Medium → Low → Lowest.
2. then **Effort, ascending** — Trivial → Low → Medium → High → Highest. Ties on Priority break toward the quicker win.
3. then **oldest first** — earliest `createdAt` wins.

The single item at the top of this ordering is exactly what `/task` claims when invoked with no arguments. This is the one place the rule is stated; other skills reference it here rather than restating it.

## Workflow

1. **Read the board and the issue list:**
   - `gh project item-list <project.number> --owner <owner> --limit 200 --format json` — all items across all statuses, with their Priority, Effort, and Status fields.
   - `gh issue list --state open --limit 200 --json number,title,labels,createdAt,updatedAt` — every open issue, to find ones missing from the board. (`createdAt` supports queue-order tiebreaks; `updatedAt` supports staleness reasoning. The Done-throughput signal in step 5 reads its own `closedAt` over closed issues, since Done items have usually closed and are absent here.)

2. **Ready queue:**
   - Filter to Status = Ready and sort by the queue-ordering rule above.
   - Present the ordered list; mark the top item as the one `/task` would pull next.
   - Treat an unset Effort as Low and an unset Priority as Medium for ordering, and flag any Ready item missing Priority, Effort, or Type — a Ready item is not fully Ready without them.

3. **In Progress — wedge detection:**
   - List every In Progress item.
   - For each, inspect its linked branch and PR (via `gh pr list` / `gh api` as needed). An item is **wedged** when any of these holds: its linked branch was merged or deleted, its PR is closed without merging, or there has been no recent commit activity on the branch.
   - Flag each wedged item and name the remedy: `/task <n>` to resume the branch, or — if the work was abandoned — reset it to Ready per `/task`'s stuck-state rule. Status does not perform the reset; it only surfaces the wedge.

4. **Stray issues:**
   - **Open but not on the board** → point at `/capture <n>` to adopt it onto the Backlog.
   - **On the board but missing required template sections** (an empty or stub Why / Implementation / Acceptance Criteria on a Ready item) → point at `/promote <n>` to specify it.

5. **Counts:**
   - Number of Backlog items awaiting `/promote`.
   - Number of items moved to Done recently — a throughput signal. Take the board's Status = Done items and read each one's issue `closedAt`, counting those inside the last ~7 days (fall back to the most recent handful if that window is empty). Done issues are usually closed (they close on merge via `closes #<n>`), so they will not appear in the `--state open` read from step 1 — fetch their `closedAt` with a targeted `gh issue list --state all --json number,closedAt` (or `--state closed`) joined to the Done items by number. **Caveat:** `closedAt` marks issue closure, which `/ship` performs at merge via `closes #<n>`, so it tracks the move to Done closely — but a board item set to Done without its issue being closed carries no `closedAt` and is counted as Done without a date.

6. **Suggested next action:**
   - Lead with the single most useful next move given the above: usually `/task` on the Ready top, but a wedged In Progress item or an empty Ready queue changes the recommendation. State it in one line.

## Notes

- Status is the map, not the move: it tells the user where the work is and what is stuck; the acting skills (`/task`, `/promote`, `/capture`) do the moving.
- All project IDs come from `.claude/project.json` — never hardcode them.
