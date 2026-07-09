---
name: capture
description: Use when the user voices a new idea, bug, task, or improvement worth tracking, or names an existing GitHub issue to file onto the project board.
argument-hint: "[idea text | issue-number]"
---

# Capture an Idea onto the Backlog

Turn a raw idea — or an already-filed GitHub issue — into a tracked Backlog item, with a dedupe check first and the user's confirmation before any write.

## Usage

```text
/capture <idea text>
/capture <issue-number>
```

Examples: `/capture add rate limiting to the login endpoint`, `/capture 88`

## Prerequisites

Read `.claude/project.json` to get project configuration. All project IDs, field IDs, and option IDs come from this file. If the file doesn't exist, stop with: "No .claude/project.json found. Run /setup-project first."

Extract and hold in context:
- `github.owner`, `github.repo`
- `github.project.number`, `github.project.nodeId`
- `github.project.fields.status.id` and the `backlog` status option
- `github.project.fields.type.id` and its options
- `labels` list

## Contract

Capture performs **no writes until the user approves** the drafted item. It **never** creates a branch, never commits, and never writes a file to disk. Its only writes — reached only after explicit approval — are: create (or adopt) the issue; on the adopt path, reshape the adopted issue's body to the template where (and only where) the user approved that reshape in steps 3 and 5; add it to the board; set Status to Backlog; and apply the confirmed labels and Type. Nothing else — and every one of these, the body reshape included, stays behind the same approval gate.

## Workflow

1. **Read the input:**
   - A bare integer → **adopt path**: an issue already exists in GitHub and the user wants it on the board.
   - Anything else → **new-idea path**: free text describing something worth tracking.

2. **Dedupe check (both paths):**
   - Fetch open issues: `gh issue list --state open --limit 200 --json number,title,labels`.
   - Fetch board items: `gh project item-list <project.number> --owner <owner> --limit 200 --format json`.
   - Compare the idea against them by meaning, not string match. If a likely duplicate exists, surface it (number + title) and ask the user whether to adopt or extend that one instead of creating a new issue. Do not create a near-duplicate silently.
   - **Adopt path additionally:** confirm the issue is not already on the board. If it already appears in the board items, stop and report — it is already tracked; point the user at `/promote` if it needs specifying.

3. **Draft the item:**
   - **Title** — a concise, specific summary.
   - **Body** — fill the template at `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md`. Stub sections are acceptable here: a Backlog item is a placeholder for future research, and `/promote` fills the specification later. Capture what is known; do not invent detail.
   - **Suggested labels** — pick from the `labels` list in project.json.
   - **Suggested Type** — pick one of the Type options in project.json (feat / fix / chore / refactor). Priority and Effort are left unset; those are determined during `/promote`.
   - Adopt path: read the existing body with `gh issue view <n>`; propose reshaping it to the template only where sections are missing, and never discard content the user wrote.

4. **Confirm before any write:**
   - Present the title, body, suggested labels, and suggested Type to the user.
   - Do nothing further until the user approves. Approval of the draft is the only trigger for step 5.

5. **On approval — create/adopt, then file to Backlog:**

   **New-idea path:**
   ```bash
   ISSUE_URL=$(gh issue create --title "..." --body "..." --label "label1,label2")
   ITEM_ID=$(gh project item-add <project.number> --owner <owner> --url "$ISSUE_URL" --format json | jq -r '.id')
   # Status = Backlog
   gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
     --field-id <fields.status.id> --single-select-option-id <fields.status.options.backlog>
   # Type (only the option the user confirmed)
   gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
     --field-id <fields.type.id> --single-select-option-id <fields.type.options.CHOSEN>
   ```

   **Adopt path:**
   ```bash
   ISSUE_URL=$(gh issue view <n> --json url --jq .url)
   # apply confirmed labels; reshape the body only if the user approved reshaping
   gh issue edit <n> --add-label "label1,label2"
   ITEM_ID=$(gh project item-add <project.number> --owner <owner> --url "$ISSUE_URL" --format json | jq -r '.id')
   # Status = Backlog, then Type as above
   gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
     --field-id <fields.status.id> --single-select-option-id <fields.status.options.backlog>
   ```

## Error Handling

- **Issue number not found (adopt path):** report it and stop — do not create a new issue under a number the user meant to adopt.
- **Issue already on the board (adopt path):** stop; it is already tracked. Point at `/promote` if it needs specifying.
- **Likely duplicate found:** surface it and let the user choose adopt/extend/create-anyway. Never create a near-duplicate without that choice.

## Notes

- Capture is the lightest intake point: idea in, Backlog item out. Specification is `/promote`'s job, not capture's.
- All project IDs come from `.claude/project.json` — never hardcode them.

## Design: model invocation is enabled

This skill deliberately leaves model invocation **on** (no `disable-model-invocation`). Intake dies on friction: the moment a trackable idea is voiced and *not* captured, it is lost, so the skill is most valuable when it can auto-trigger the instant the user surfaces an idea, bug, or improvement. The usual hazard of auto-triggering — an unwanted side effect firing on a false positive — does not apply here, because the Contract above blocks every board write behind explicit approval. A false trigger costs at most a drafted suggestion the user declines; it can never create or mutate anything. That asymmetry (high value on a true trigger, near-zero cost on a false one) is why auto-invocation is the right call for capture and the wrong call for the write-heavy skills that keep `disable-model-invocation: true`.
