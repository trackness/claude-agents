---
name: promote
description: Use when a Backlog idea needs to become implementable — a rough issue turned into a Ready, fully-specified item.
disable-model-invocation: true
argument-hint: "<issue-number>"
---

# Promote Backlog Issue to Ready

Promote a Backlog issue to Ready status by researching, brainstorming, and writing a full specification.

## Usage

```text
/promote <issue-number>
```

Example: `/promote 42`

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`
- `github.project.number`, `github.project.nodeId`
- All field IDs and option IDs from `github.project.fields`
- `labels` list — the label set this repo uses, so the promoted issue is labelled from the sanctioned vocabulary rather than an invented one

In the commands below, a placeholder like `<fields.priority.options.CHOSEN>` (and its Effort/Type equivalents) means the option ID under that field whose name matches the value you picked for this issue — e.g. `<fields.priority.options.high>` when Priority is High. `CHOSEN` is never literal; resolve it to the concrete option key.

## Workflow

1. **Find the Backlog issue:**
   - `gh issue view <n>` to fetch the current issue body
   - Verify it exists on the project with Backlog status via `gh project item-list <project.number> --owner <owner> --limit 200 --format json`
   - If not Backlog: warn and confirm before proceeding

2. **Research the implementation (dispatched read-only readers):**

   The bulk sweep is not main-loop work. Dispatch one or more read-only reader subagents via the Agent tool to sweep the codebase, and synthesize the structured map they return rather than reading the tree yourself. Size the fan-out to the work — a narrow idea may need one reader, a cross-cutting one several partitioned by area.

   Each reader returns:
   - **Affected files** — the files a change would touch, each with its single responsibility.
   - **Existing patterns and constraints** — the conventions, abstractions, and invariants the work must fit.
   - **Integration points** — the seams (callers, callees, config, data) the change wires into.
   - **Related open issues** — from `gh issue list --state open --limit 200`, the issues that are potential dependencies or overlaps.
   - **Effort signals** — the size and complexity evidence that grounds the Effort estimate (Trivial/Low/Medium/High/Highest) and the Priority estimate (Critical/High/Medium/Low/Lowest).

   **Dispatch discipline** — every reader prompt is **focused** (one bounded slice, non-overlapping scope), **self-contained** (it sees only what the prompt gives it; state the paths or area to cover and that it must not create issues, edit the board, branch, or commit — it reads and reports only), and **output-format-specified** (the exact map shape above, so no second round-trip). This is the same fan-out style as audit's investigation.

   The orchestrating session keeps only **targeted reads during the step-3 dialogue** — when a specific question needs a primary-source detail the map did not settle, it opens that one file surgically. That is bounded and surgical; it is never a re-sweep of the tree.

3. **Specify the issue (inline Socratic dialogue):**

   This skill owns its control flow — do not invoke external brainstorming or planning skills within it. Run the dialogue yourself, grounded in the step-2 research (affected files, related issues, effort estimate, existing patterns).

   - Ask clarifying questions **one at a time**, never in a batch. Prefer multiple-choice questions (numbered options) over open-ended ones so the user can answer fast.
   - Once intent is clear, present **2–3 approaches with their tradeoffs, leading with your recommendation** and the reason for it.
   - Apply YAGNI: cut everything the issue does not actually need. A narrower, sharper spec beats a speculative one.
   - The output of this dialogue is a single filled-in issue body using the template at `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md` — and NOTHING else. No plan file, no commit, no handoff to another skill. The issue body is the only artifact.
   - The issue title may be refined during the dialogue.
   - If the dialogue reveals the issue is Highest-effort and should be broken down, draft sub-issues (each a full template body) instead of one.

   **Final Ready check (spec self-review).** Before presenting the draft, confirm it meets the **Ready invariant** defined in the header comment of `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md` (body complete per the template; Effort, Priority, and Type set; not blocked by an open issue). The four checks below are the mechanical teeth that verify it:
   - **Placeholder scan** — no "TBD", no "add appropriate X", no unfilled template slots, no "similar to …" hand-waves.
   - **Internal consistency** — Why, Implementation, Files, Testing, and Acceptance Criteria agree with one another; no section contradicts another.
   - **Scope check** — every item in scope is needed, nothing speculative survived the YAGNI cut, and the Effort estimate matches the described work.
   - **Ambiguity check** — a fresh implementer could build this without asking a question. Any sentence open to two readings gets rewritten.

   **Adversarial spec-review (mandatory — every promotion).** After the four checks above pass, ALWAYS dispatch one fresh-context spec-review subagent via the Agent tool. Give it ONLY the drafted issue body — no research map, no dialogue history, no reasoning that led here. Charter it to refute: hunt gaps, contradictions, unstated assumptions, and untestable acceptance criteria, and report its findings without trusting the draft. A fresh mind reads the spec the way the future implementer will: cold. Fold its findings back into the body before presenting the draft in step 5. This dispatch is never skipped — not for a small issue, not for an obvious one, not under time pressure, not because the self-review already passed.

4. **Won't Do exit (when the honest conclusion is "don't do this"):**

   Promotion does not always end in a spec. If the research or the dialogue concludes the work should not happen — the idea is obsolete, already solved elsewhere, out of scope for this project, or not worth its cost — do not force a spec into existence. State the reasoning to the user and ask for explicit confirmation to close the issue as Won't Do. Only on that confirmation, run all three of:
   ```bash
   # Reasoning comment first, so the trail survives the close
   gh issue comment <n> --body "Won't Do: <concrete reasoning for not doing this>"
   # Close the issue as not planned
   gh issue close <n> --reason "not planned"
   # Board Status = Won't Do
   ITEM_ID=$(gh project item-list <project.number> --owner <owner> --limit 200 --format json | jq -r '.items[] | select(.content.number == <n>) | .id')
   gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
     --field-id <fields.status.id> --single-select-option-id <fields.status.options.wontDo>
   ```
   This is a terminal exit — no branch, no further spec, no board Status other than Won't Do. Without the user's explicit confirmation, close nothing and edit nothing. If the conclusion is instead "do this", skip this step and continue to step 5.

5. **Draft the updated issue:**
   - Present the full issue body, proposed labels, Type, Priority, and Effort to the developer for review
   - Show the diff from the current Backlog issue body to the proposed Ready issue body
   - Also present any proposed relationships (dependencies, sub-issue parent)
   - If breaking into sub-issues: present the parent and all proposed children

6. **On user approval:**
   - **Single issue path:**
     ```bash
     # Update issue body and labels
     gh issue edit <n> --body "..." --add-label "label1,label2"
     # Get project item ID
     ITEM_ID=$(gh project item-list <project.number> --owner <owner> --limit 200 --format json | jq -r '.items[] | select(.content.number == <n>) | .id')
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
     Set dependencies via the mutation at `${CLAUDE_PLUGIN_ROOT}/shared/queries/add-blocked-by.graphql` if applicable.

   - **Breakdown path (Highest-effort):**
     The original Backlog issue becomes the parent — update its body to describe the overall effort. Set Status = Ready, Priority, Effort, Type on the parent (it carries all project fields). Create child issues with full template bodies. Add children via the mutation at `${CLAUDE_SKILL_DIR}/queries/add-sub-issue.graphql`. Do NOT add children to the Project board. Set dependencies on children via `${CLAUDE_PLUGIN_ROOT}/shared/queries/add-blocked-by.graphql` as needed.

## Error Handling

- **Issue not found:** List Backlog issues and exit
- **Issue is not in Backlog status:** Warn — "Issue is already in Ready/In Progress/Done status"

## Notes

- Promote is pure API calls — no file changes, no branch, no commit needed
- The core value: taking a bare idea and giving it adequate attention through research and brainstorming to produce a fully-specified, implementable issue
