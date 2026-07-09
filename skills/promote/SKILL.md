---
name: promote
description: Promote a Backlog issue to Ready by researching, brainstorming, and writing a full specification. Use when a Backlog idea needs to become implementable.
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

## Workflow

1. **Find the Backlog issue:**
   - `gh issue view <n>` to fetch the current issue body
   - Verify it exists on the project with Backlog status via `gh project item-list <project.number> --owner <owner> --limit 200 --format json`
   - If not Backlog: warn and confirm before proceeding

2. **Research the implementation:**
   - Read relevant source files to understand the current codebase
   - Identify which files would need to change
   - Estimate Effort (Trivial/Low/Medium/High/Highest) and Priority (Critical/High/Medium/Low/Lowest)
   - Check open GitHub issues (`gh issue list --state open --limit 200`) for related work (potential dependencies)

3. **Brainstorm:**
   - Invoke the `superpowers-extended-cc:brainstorming` skill, explicitly summarising the findings from step 2 (affected files, related issues, effort estimate, existing patterns) as input context
   - Use the brainstorming output to draft the full issue body using the template at `${CLAUDE_PLUGIN_ROOT}/shared/templates/issue-body.md`
   - The issue title may be refined during brainstorming
   - If brainstorming reveals the issue is Highest-effort and should be broken down, draft sub-issues instead

4. **Draft the updated issue:**
   - Present the full issue body, proposed labels, Type, Priority, and Effort to the developer for review
   - Show the diff from the current Backlog issue body to the proposed Ready issue body
   - Also present any proposed relationships (dependencies, sub-issue parent)
   - If breaking into sub-issues: present the parent and all proposed children

5. **On user approval:**
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
       --field-id <fields.priority.id> --single-select-option-id <priority-option-id>
     # Effort
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.effort.id> --single-select-option-id <effort-option-id>
     # Type
     gh project item-edit --project-id <project.nodeId> --id "$ITEM_ID" \
       --field-id <fields.type.id> --single-select-option-id <type-option-id>
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
