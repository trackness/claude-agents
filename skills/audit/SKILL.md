---
name: audit
description: Use when the user wants a codebase health check, a gap analysis across the repo, or wants declared-but-unfiled work (TODOs, ROADMAP notes, doc checklists) harvested onto the project board.
disable-model-invocation: true
---

# Audit Repository

Sweep the codebase for gaps and for intent that was declared in the code but never filed, and turn both into suggested GitHub Issues on the project board.

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`
- `github.project.number`, `github.project.nodeId`
- All field IDs and option IDs from `github.project.fields`
- `labels` list

## Stack detection

Before any analysis, detect the project's technology stack by checking for these marker files in the repository root, then read every matching reference so the sweep is judged against the right stack-specific criteria:

| File                                                                           | Stack                        | Reference to load                                                        |
|--------------------------------------------------------------------------------|------------------------------|--------------------------------------------------------------------------|
| `package.json` or `tsconfig.json`                                              | TypeScript / React / Node.js | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/lang-typescript.md` |
| `go.mod`                                                                       | Go                           | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/lang-go.md`         |
| `Cargo.toml`                                                                   | Rust                         | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/lang-rust.md`       |
| `pyproject.toml`, `setup.py`, or `requirements.txt`                            | Python                       | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/lang-python.md`     |
| `Dockerfile`, `compose.yaml`, or `docker-compose.*`                            | Docker                       | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/infra-docker.md`    |
| `migrations/`, `db/`, `prisma/`, `alembic.ini`, `diesel.toml`, or `knexfile.*` | Database                     | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/infra-database.md`  |

A repo may match several rows — load **all** matching references. These loaded criteria feed the stack-reference stream of the investigation fan-out below.

## The dimensions

The gap analysis is chartered against these dimensions. Each investigation sweep is scoped to a group of them; nothing outside this list is invented, and no dimension is silently dropped.

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

## Workflow

Orchestration and the per-item approval gate live here in the main loop. The bulk reading — the repo sweeps, the stack-reference review, and the ingestion harvest — is dispatched to parallel subagents. The main loop never hands a subagent the power to write: subagents read and report, and only the main loop, with the user's per-item approval, creates issues or edits the board.

1. **Read the lightweight state (main loop):**
   - Read CLAUDE.md — understand what the project does and its tech stack.
   - Fetch all project items: `gh project item-list <project.number> --owner <owner> --limit 200 --format json` — note all items across all statuses (Ready, In Progress, Done, Won't Do, Backlog).
   - Fetch all open GitHub issues: `gh issue list --state open --limit 200 --json number,title,labels` — these are already tracked; do not duplicate them.
   - Take a cheap measure of repo size (`git ls-files | wc -l`, top-level layout) — this sizes the fan-out in step 2.
   - If the user named a scope (a single dimension, a directory, or a concern), narrow every stream below to that scope instead of sweeping the whole tree.

2. **Investigation fan-out (parallel subagents via the Agent tool):**

   The Agent tool is the primary, universally available path — dispatch the investigation as parallel read-only subagents and synthesize what they return. Three kinds of stream run:
   - **Dimension-group sweeps** — partition the dimensions above into groups and give each group its own subagent to read the relevant source, tests, config, and docs and report gaps. Group related dimensions together (e.g. security + reliability + production; testing + performance; ux + accessibility; architecture + documentation + devops + feature) rather than one agent per dimension.
   - **Stack-reference review** — one or more subagents apply the criteria from the stack references loaded in *Stack detection* to the code that matches each stack.
   - **Ingestion harvest** — subagents sweep for declared-but-unfiled intent (see step 3).

   **Fan-out scales with repo size, not a fixed dimension count.** A small repo may need two or three subagents total; a large monorepo may need many, partitioned by directory as well as by dimension. Size the fan-out to the tree, then charter each subagent narrowly enough to finish in one pass.

   **Dispatch discipline** — every subagent prompt must be:
   - **Focused** — one clearly bounded slice of the investigation, with non-overlapping scope. Two agents reading the same files waste work and double-report.
   - **Self-contained** — the subagent sees only what the prompt gives it. Include the paths/dimensions/criteria it must cover, the loaded stack criteria it should apply, and the fact that it must not create issues, edit the board, branch, or commit — it reads and reports only.
   - **Output-format-specified** — state the exact shape to return: per finding, the dimension tag, the file:line location, the problem, the impact, and a recommended Ready-or-Backlog disposition. An unspecified format forces a second round-trip.

   **Common dispatch mistakes to avoid:** overlapping scopes that double-count; assuming a subagent shares your context (it does not — spell it out); leaving the return format unstated; dispatching work with sequential dependencies as if it were parallel (only independent reads fan out); letting a subagent write instead of report.

   Each subagent reports in the four-state vocabulary: **DONE** (swept its scope, findings attached), **DONE_WITH_CONCERNS** (findings attached, but flag caveats), **BLOCKED** (could not complete — say why), **NEEDS_CONTEXT** (needs input the prompt did not supply before it can proceed). Re-dispatch BLOCKED and NEEDS_CONTEXT streams with the missing piece rather than accepting a partial sweep.

   **Workflow tool (optional upgrade).** Where a project- or user-level `.claude/workflows/` orchestration is available, it may drive this fan-out instead of manual Agent dispatch. It is paid-plan-gated and cannot ship inside this plugin, so it is never assumed — the Agent-tool path above is always the baseline.

3. **Ingestion harvest (declared-but-unfiled intent):**

   Harvest intent that lives in the repo but was never filed as an issue. This is a broad, model-driven read — the subagent judges what counts as real declared work, not a fixed regex match:
   - Inline markers: `TODO`, `FIXME`, `HACK`, and equivalents in code comments.
   - Standalone intent docs: `TODO.md`, `ROADMAP.md`, `NOTES`, scratch/planning markdowns.
   - Unchecked checklist items in documentation (README/docs task lists, design-doc open questions).

   Each harvested item carries its **source location** through to the issue body (e.g. `Source: src/api/handler.ts:88 (TODO comment)` or `Source: ROADMAP.md — "rate-limit the upload endpoint"`), so the trail from declared intent to filed issue is auditable. Harvested items enter the exact same draft → dedupe → approve → create pipeline as the dimension findings; there is no separate track.

4. **Adversarial verification pass (before findings reach the approval gate):**

   Do not trust the subagent reports at face value — a fan-out that reports clean or over-reports is a known failure mode. Run a verification pass over the collected findings before any of them reach the user:
   - Spot-check each finding against the actual code it cites — a finding whose file:line does not say what the report claims is dropped. A fabricated finding either wastes an approval or gets a non-bug "fixed".
   - Reconcile overlaps from the fan-out — same gap reported by two streams collapses to one finding.
   - Treat **"cannot verify"** as a valid outcome: a finding you cannot confirm against the code is demoted or dropped, never passed through on the subagent's word.
   Shape this pass like a skeptical reviewer of the subagents' work, not a rubber stamp.

5. **Cross-reference (dedupe against what already exists):**
   - Do not suggest tasks already open in GitHub Issues.
   - Do not suggest tasks closed with Won't Do status in Projects.
   - Check Backlog and Ready issues in the project for overlap — suggest promoting a Backlog item rather than filing a duplicate.

6. **Draft output:**
   - For each surviving finding, recommend a status:
     - **Ready** — well-understood, concrete findings with a clear implementation path. Draft using the issue body template at `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md`. A Ready draft must satisfy the Ready invariant: body complete per the template, with Effort, Priority, and Type set, and not blocked by an open issue.
     - **Backlog** — speculative or broad findings that need more research before implementation. Draft with sufficient context for a future `/promote` invocation (idea, motivation, known constraints).
   - For ingestion findings, record the source location inside the drafted body.
   - Present all suggestions to the developer for review before creating anything.

   **Do not soft-pedal findings.** If something is a structural problem, a gap, or a smell — raise it as an issue. Phrases like "acceptable at this scale", "minor", "fine for now", or "not worth it given the project size" are forbidden. Every finding warrants an issue — if it does not, it should not appear in the audit at all.

7. **On user approval (per item):**
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

8. **Draft the cleanup issue (final act):**

   Once ingestion findings have been filed, the source markers they came from are now duplicated on the board and should be removed from the code — but **audit never commits**, so it does not remove them itself. Instead, draft one final Ready issue: "remove task artifacts migrated to the board". Its Implementation section lists the exact source locations harvested in step 3 (the TODO/FIXME comments, the ROADMAP entries, the checklist items) paired with the issue numbers they became, so a future `/task` run can delete each marker with a clear trail. This cleanup issue flows through `/task` and `/ship` like any other — it is the only place the migrated intent turns into a code change, and it happens on a branch, not in the audit.

## Notes

- Audit is pure API calls plus read-only investigation — no file changes, no branch, no commit. The only code change it produces is the cleanup issue in step 8, which is filed, not applied.
- The gap analysis is exhaustive across the dimensions — do not let the fan-out drop one.
- Subagents read and report; the main loop holds the approval gate and performs every write.
- Per-item user approval is required before creating any issue.
- All project IDs come from `.claude/project.json` — never hardcode them.
