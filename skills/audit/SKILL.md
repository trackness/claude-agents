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

In the commands below, a placeholder like `<fields.priority.options.CHOSEN>` (and its Effort/Type equivalents) means the option ID under that field whose name matches the value you picked for this issue — e.g. `<fields.priority.options.high>` when Priority is High. `CHOSEN` is never literal; resolve it to the concrete option key.

## Stack detection

Before any analysis, detect the project's technology stack by checking for these marker files in the repository root, then read every matching reference so the sweep is judged against the right stack-specific criteria:

| File                                                                           | Stack                        | Reference to load                                                        |
|--------------------------------------------------------------------------------|------------------------------|--------------------------------------------------------------------------|
| `package.json` or `tsconfig.json`                                              | JavaScript / TypeScript / React / Node.js | `${CLAUDE_PLUGIN_ROOT}/shared/references/stacks/lang-typescript.md` |
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
- `#infrastructure` — server setup, health checks, configuration wiring, database setup

## Workflow

Orchestration and the per-item approval gate live here in the main loop. The bulk reading — the repo sweeps, the stack-reference review, the ingestion harvest, and the adversarial verification of what they report — is dispatched to parallel subagents. The main loop never hands a subagent the power to write: subagents read and report, and only the main loop, with the user's per-item approval, creates issues or edits the board.

1. **Read the lightweight state (main loop):**
   - Read CLAUDE.md — understand what the project does and its tech stack.
   - Fetch all project items: `gh project item-list <project.number> --owner <owner> --limit 200 --format json` — note all items across all statuses (Ready, In Progress, Done, Won't Do, Backlog).
   - Fetch all open GitHub issues: `gh issue list --state open --limit 200 --json number,title,labels` — these are already tracked; do not duplicate them.
   - Take a cheap measure of repo size (`git ls-files | wc -l`, top-level layout) — this sizes the fan-out in step 2.
   - If the user named a scope (a single dimension, a directory, or a concern), narrow every stream below to that scope instead of sweeping the whole tree.
   - **Record the working-tree baseline** — run `git status --porcelain` before dispatching any subagent and keep the output. The read-only gate re-runs after every subagent wave and compares against this snapshot to prove the investigation wrote nothing.

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

   Each subagent reports in the four-state vocabulary: **DONE** (swept its scope, findings attached), **DONE_WITH_CONCERNS** (findings attached, but flag caveats), **BLOCKED** (could not complete — say why), **NEEDS_CONTEXT** (needs input the prompt did not supply before it can proceed). Re-dispatch BLOCKED and NEEDS_CONTEXT streams with the missing piece rather than accepting a partial sweep. This fan-out is a read-only wave: once its streams (including the step-3 ingestion harvest) have all returned, run the **Read-only gate (runs after every subagent wave)** below before any finding is consumed.

   **Workflow tool (optional upgrade).** Where a project- or user-level `.claude/workflows/` orchestration is available, it may drive this fan-out instead of manual Agent dispatch. It is paid-plan-gated and cannot ship inside this plugin, so it is never assumed — the Agent-tool path above is always the baseline.

3. **Ingestion harvest (declared-but-unfiled intent):**

   Harvest intent that lives in the repo but was never filed as an issue. This is a broad, model-driven read — the subagent judges what counts as real declared work, not a fixed regex match:
   - Inline markers: `TODO`, `FIXME`, `HACK`, and equivalents in code comments.
   - Standalone intent docs: `TODO.md`, `ROADMAP.md`, `NOTES`, scratch/planning markdowns.
   - Unchecked checklist items in documentation (README/docs task lists, design-doc open questions).

   Each harvested item carries its **source location** through to the issue body (e.g. `Source: src/api/handler.ts:88 (TODO comment)` or `Source: ROADMAP.md — "rate-limit the upload endpoint"`), so the trail from declared intent to filed issue is auditable. Harvested items enter the exact same draft → dedupe → approve → create pipeline as the dimension findings; there is no separate track. This harvest runs inside the same investigation wave as step 2, so the **Read-only gate (runs after every subagent wave)** below governs it too.

### Read-only gate (runs after every subagent wave)

This gate is a hard, fail-closed post-condition on every subagent wave. Every subagent — the investigation fan-out (steps 2–3) and the verification wave (step 4) alike — was chartered to read and report, never to write. The moment a wave's subagents have all returned — and before anything downstream consumes what they reported — prove that guarantee held. Run:

```bash
git status --porcelain
```

Its output must be byte-for-byte identical to the baseline recorded in step 1. Any added, changed, or removed line means a subagent created, modified, or deleted a file — a read-only violation, not a finding. On any difference, **HALT the audit immediately**: do not advance to any further wave, do not dedupe, do not draft, do not open the approval gate, and create nothing. Report exactly what changed — the differing `git status --porcelain` lines, verbatim — and stop until the tree is restored to the baseline and the cause is understood. This gate is mechanical and fail-closed: a changed tree is always a halt, never a caveat to note and pass.

4. **Adversarial verification pass (parallel read-only skeptic subagents):**

   Do not trust the subagent reports at face value — a fan-out that reports clean or over-reports is a known failure mode. But verifying the findings is itself bulk reading: confirming each one means opening the code it cites, and doing that in the main loop stacks dozens of file reads into root context — the exact load the fan-out exists to keep out. So the verification pass is a **second parallel wave of read-only subagents**, chartered as skeptics whose job is to **refute the findings, not rubber-stamp them**.

   Group the collected findings so each group's cited code is coherent (by stream, by dimension, or by directory), and hand each group to one skeptic subagent. Each skeptic:
   - **Checks every finding against the actual code it cites** — open the file:line and confirm it says what the report claims. A finding whose cited location does not bear out the claim does not survive on the reporter's word.
   - **Reconciles overlaps within its own group** — two findings naming the same gap collapse to one.
   - **Returns a per-finding verdict**: **CONFIRMED** (the cited code bears out the claim), **REFUTED** (the cited code contradicts it), or **CANNOT-VERIFY** (the cited location does not confirm it and the skeptic cannot confirm it elsewhere). **CANNOT-VERIFY demotes or drops the finding — never pass it through on the reporter's word.** Attach the evidence behind every verdict.

   Charter each skeptic with the same **dispatch discipline** as step 2: **focused** (one coherent group of findings, non-overlapping with the other skeptics), **self-contained** (the prompt carries the findings to check, their cited file:line locations, and the refute-not-rubber-stamp charter; the subagent must not create issues, edit the board, branch, or commit — it reads and reports only), and **output-format-specified** (per finding: the CONFIRMED / REFUTED / CANNOT-VERIFY verdict and its evidence). Each skeptic also reports its own completion in the four-state vocabulary — **DONE**, **DONE_WITH_CONCERNS**, **BLOCKED**, **NEEDS_CONTEXT** — and BLOCKED or NEEDS_CONTEXT streams are re-dispatched with the missing piece, never accepted as a partial verification.

   When the skeptics return, run the **Read-only gate (runs after every subagent wave)** above again before any verdict reaches the dedupe or a draft. Then reconcile overlaps **across** groups in the main loop — the same gap surfaced by two different skeptic groups collapses to one finding. This cross-group reconciliation stays in the main loop because it needs the full surviving set and is cheap; only the per-group verification and within-group merge fan out.

5. **Cross-reference (dedupe against what already exists):**
   - Do not suggest tasks already open in GitHub Issues.
   - Do not suggest tasks closed with Won't Do status in Projects.
   - Check Backlog and Ready issues in the project for overlap — suggest promoting a Backlog item rather than filing a duplicate.

6. **Draft output:**
   - For each surviving finding, recommend a status:
     - **Ready** — well-understood, concrete findings with a clear implementation path. Draft using the issue body template at `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md`. A Ready draft must satisfy the **Ready invariant** defined in that template's header comment (body complete per the template; Effort, Priority, and Type set; not blocked by an open issue) before it may be filed as Ready.
     - **Backlog** — speculative or broad findings that need more research before implementation. Draft with sufficient context for a future `/promote` invocation (idea, motivation, known constraints).
   - For ingestion findings, record the source location inside the drafted body.
   - Present all suggestions to the developer for review before creating anything.

   **Do not soft-pedal findings.** If something is a structural problem, a gap, or a smell — raise it as an issue. Phrases like "acceptable at this scale", "minor", "fine for now", or "not worth it given the project size" are forbidden. Every finding warrants an issue — if it does not, it should not appear in the audit at all.

7. **On user approval (per item):**
   - **Ready findings:**
     ```bash
     ISSUE_URL=$(gh issue create --title "..." --body "..." --label "label1,label2")
     ITEM_ID=$(gh project item-add <project.number> --owner <owner> --url "$ISSUE_URL" --format json | jq -r '.id')
     ```
     **Attach dependencies before the status write.** Add every blockedBy relationship this finding carries via the mutation at `${CLAUDE_PLUGIN_ROOT}/shared/queries/add-blocked-by.graphql`, so the dependency set is on record before the Status is decided.

     **Pre-Ready dependency check (limb 5 of the invariant).** Query the state of every blockedBy relationship just attached and confirm each blocker is CLOSED with stateReason COMPLETED. Then set the Status accordingly:
     - **Every blocker closed/completed (or none):** file it as Ready with its project fields:
       ```bash
       # Status = Ready
       gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
         --field-id <fields.status.id> --single-select-option-id <fields.status.options.ready>
       # Priority
       gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
         --field-id <fields.priority.id> --single-select-option-id <fields.priority.options.CHOSEN>
       # Effort
       gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
         --field-id <fields.effort.id> --single-select-option-id <fields.effort.options.CHOSEN>
       # Type
       gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
         --field-id <fields.type.id> --single-select-option-id <fields.type.options.CHOSEN>
       ```
     - **Any blocker still open:** the finding is NOT Ready — file it as Backlog instead (the dependency stays recorded from the attach step) and tell the user it stays blocked until the open blocker closes:
       ```bash
       # Status = Backlog (blocked by an open issue)
       gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
         --field-id <fields.status.id> --single-select-option-id <fields.status.options.backlog>
       ```

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
