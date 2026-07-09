# Claude Development Guide

## Hooks Enforcement

The gh-pm plugin ships hooks that intercept tool calls before they run. They are guardrails, not guarantees: they catch the common mechanical mistakes at the point of action, they do not claim to close every possible path around them.

| Hook | Enforces |
|------|----------|
| `no-commit-main.sh` | No direct commits to the default branch (amend allowed) |
| `no-hook-bypass.sh` | No `--no-verify` (or its abbreviations) on git commands |
| `enforce-pr-reviewer.sh` | PR reviews must run the `gh-pm:pr-reviewer` agent |
| `enforce-merge-gate.sh` | `gh pr merge` pauses for your confirmation when `ship.autoMerge` is `false` |

---

## Skill Routing

Work is tracked on the GitHub Project board, and every state change goes through a gh-pm skill. The board only reflects reality if work actually routes through these skills — a change made outside them is invisible to the board and to everyone reading it.

| Situation | Skill |
|-----------|-------|
| A new idea, bug, or improvement worth tracking | `/capture` |
| Turn a Backlog idea into an implementable spec | `/promote <n>` |
| Start (or resume) work on a Ready issue, or pull the next one off the queue | `/task [n ...]` |
| Land a finished branch: commit, PR, review, CI, merge | `/ship` |
| Codebase health check; harvest TODO/FIXME/ROADMAP intent onto the board | `/audit` |
| See board state, what to work on next, and what is stalled | `/status` |
| Bootstrap this repo's project, labels, and config | `/setup-project` |

**Red flags — the rationalizations that route work around the board:**

- "This is just a quick fix, I'll skip the issue." → It still goes through `/task`. Small work is still tracked work.
- "I'll file that idea later." → Later is where ideas die. `/capture` it now; it is one command and no commitment.
- "The diff is small enough to merge by eye." → It still goes through `/ship`. The reviewer and CI gate exist for the change you were sure was fine.
- "I'll just set the status by hand." → `/task`, `/promote`, and `/ship` own the board writes; a hand-edit desyncs the board from the work.

---

## Task Management

All development tasks are tracked as GitHub Issues. The GitHub Project board is the single source of truth. Configuration is in `.claude/project.json`.

Query the board: `gh project item-list <projectNumber> --owner <owner> --limit 200 --format json`

### Effort Scale

| Value     | Meaning                                             |
|-----------|-----------------------------------------------------|
| Trivial   | Minimal change, near-zero complexity                |
| Low       | Small, well-understood change                       |
| Medium    | Moderate scope, some design decisions               |
| High      | Substantial scope, significant implementation work  |
| Highest   | Very large scope; consider breaking into sub-issues |

> Medium, High, and Highest effort issues are decomposed before implementation.

### Priority Scale

| Value    | Meaning                  |
|----------|--------------------------|
| Critical | Must be done immediately |
| High     | Important, do soon       |
| Medium   | Normal priority          |
| Low      | Nice to have             |
| Lowest   | Someday/maybe            |

### Branch Naming

```text
<type>/<short-description>
```

feat/, fix/, chore/, refactor/

### Issue Body Template

Use the standard template from the gh-pm plugin. All issues created by `/audit`, `/promote`, and `/capture` follow this format: Why, Implementation, Files, Testing, Acceptance Criteria.

### Merge Policy

`/ship` reads `ship.autoMerge` from `.claude/project.json` to decide what happens after a PR passes review and CI:

- `true` (the default, and the value when the key is absent) — `/ship` merges the PR itself once the `gh-pm:pr-reviewer` verdict is APPROVE and CI is green.
- `false` — `/ship` stops with the PR ready and waits for your explicit instruction to merge. The `enforce-merge-gate.sh` hook is the mechanical backstop for this case: it turns `gh pr merge` into a confirmation prompt.

---

## Pre-commit Hooks

<!-- Configure your lefthook pre-commit hooks and document them here -->

---

## Project Info

**Description:** <!-- What this project does, in one sentence -->

**Tech Stack:** <!-- List languages, frameworks, databases, deployment targets -->

**Structure:** <!-- Key directories and what they contain -->

**Testing:** `<testCommand>`

**Deployment:** <!-- How this project is deployed -->
