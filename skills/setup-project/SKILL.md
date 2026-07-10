---
name: setup-project
description: Use to onboard a repository into the gh-pm workflow — a brand-new repo or an existing one being adopted. Run once per repo.
disable-model-invocation: true
---

# Setup Project

Onboard a repository into the gh-pm workflow: a GitHub Project with standard fields, the standard label set, local config in `.claude/project.json`, and a starter CLAUDE.md.

Run this once per repo. It works two ways:
- **New repo** — creates the GitHub repo, project, fields, and labels from scratch.
- **Existing repo (adoption)** — reconciles with what is already there: reuses an existing project and labels, leaves an existing CLAUDE.md untouched, and non-destructively migrates an existing `.claude/project.json` by adding only the keys it is missing.

Idempotent — safe to re-run; every step checks before it creates, and nothing already present is overwritten.

## Workflow

### Phase 1: Prerequisites (fail fast)

**Step 1: Check system dependencies**

`gh` and `jq` are hard requirements — the skill (and every other gh-pm skill and hook) cannot run without them:

```bash
gh --version
jq --version
```

If either is missing, print a single command and stop:
```
Missing dependencies. Install with: brew install <missing tools>
```
Stop. Do not proceed.

Then probe for optional consumer-repo tooling — detected and noted if present, never blocking:

```bash
task --version    2>/dev/null && echo "task present"
lefthook version  2>/dev/null && echo "lefthook present"
```

Neither is used by the plugin itself. Their presence is only a signal about how the consumer repo builds and tests — note whichever is installed and carry that forward to the test-command detection in Step 12 (a `task` runner suggests a `Taskfile.yml` with a `test` task). Missing either one is fine; do not print a missing-dependency error for them and never stop on their account.

**Step 2: Check GitHub authentication and token scopes**

```bash
gh auth status
```

Required scopes: `project`, `repo`, `read:org`. Check the output for these. If any are missing, print:
```
Missing GitHub token scopes. Run: gh auth refresh -s project,repo,read:org
```
Stop. Do not proceed.

**Step 3: Detect or create repository**

Check if the current directory is a git repo with a GitHub remote:

```bash
gh repo view --json owner,name,id
```

If this succeeds, capture `owner`, `name`, and `id` (the repository node ID).

If this fails (no git repo or no GitHub remote):
1. Derive the repo name from the current directory name (`basename "$PWD"`)
2. Detect the GitHub owner from `gh auth status` (authenticated user)
3. `git init` if not already a git repo
4. Create the GitHub repo: `gh repo create <owner>/<dir-name> --private --source . --push`
5. Capture `owner`, `name`, and `id` from the newly created repo

### Phase 2: GitHub Project

**Step 4: Check for existing project**

```bash
gh project list --owner <owner> --format json
```

Look for an existing project linked to this repo. If found, ask the user: "Found existing project '<name>'. Use it? (y/n)". If yes, capture its number and node ID, then skip **only** Step 5 (project creation) and continue at Step 6 — Steps 6-9 must still run to capture the Status/Priority/Effort/Type field IDs and option IDs that Step 14 writes into `.claude/project.json`. If no, create a new one at Step 5.

**Step 5: Create the GitHub Project**

```bash
gh project create --owner <owner> --title "<Repo Name> Backlog" --format json
```

Capture the project number and node ID.

**Step 6: Configure Status field**

Status is a built-in field. Query the project to get the Status field ID and its default options:

```bash
gh project field-list <number> --owner <owner> --format json
```

The standard Status options are:
1. Backlog
2. Ready
3. In Progress
4. Done
5. Won't Do

Add any missing options and capture all option IDs. Use the mutation at `${CLAUDE_SKILL_DIR}/queries/update-status-field.graphql`. Substitute the status field ID.

**Warning:** This mutation replaces all existing Status options. If the project has custom statuses beyond the standard 5, they will be lost. Fetch existing options first and verify before running.

**Step 7: Create Priority field**

First check whether the field already exists (it will on the reuse-existing-project path) with `gh project field-list <number> --owner <owner> --format json`. If a `Priority` field is present, capture its field ID and all option IDs and move on — do not re-create it. Otherwise create it with the mutation at `${CLAUDE_SKILL_DIR}/queries/create-priority-field.graphql` (substitute the project node ID) and capture field ID and all option IDs. Either path must end with the field ID and option IDs captured for Step 14.

**Step 8: Create Effort field**

First check whether the field already exists with `gh project field-list <number> --owner <owner> --format json`. If an `Effort` field is present, capture its field ID and all option IDs and move on — do not re-create it. Otherwise create it with the mutation at `${CLAUDE_SKILL_DIR}/queries/create-effort-field.graphql` (substitute the project node ID) and capture field ID and all option IDs. Either path must end with the field ID and option IDs captured for Step 14.

**Step 9: Create Type field**

First check whether the field already exists with `gh project field-list <number> --owner <owner> --format json`. If a `Type` field is present, capture its field ID and all option IDs and move on — do not re-create it. Otherwise create it with the mutation at `${CLAUDE_SKILL_DIR}/queries/create-type-field.graphql` (substitute the project node ID) and capture field ID and all option IDs. Either path must end with the field ID and option IDs captured for Step 14.

**Step 10: Link project to repository**

Use the mutation at `${CLAUDE_SKILL_DIR}/queries/link-project-to-repo.graphql`. Substitute the project node ID and repository node ID.

### Phase 3: Labels

**Step 11: Create standard labels**

Create each label on the repo. Skip any that already exist (gh returns an error for duplicates — treat as success).

```bash
gh label create security     --color "d73a49" --description "Auth, validation, CORS, XSS, injection" 2>/dev/null
gh label create infrastructure --color "0075ca" --description "Server setup, health checks, config, database" 2>/dev/null
gh label create testing      --color "e4e669" --description "Unit, integration, E2E tests" 2>/dev/null
gh label create reliability  --color "f9d0c4" --description "Retry logic, logging, migrations, backups" 2>/dev/null
gh label create ux           --color "c5def5" --description "Interactions, keyboard, mobile, polish" 2>/dev/null
gh label create accessibility --color "bfd4f2" --description "ARIA, screen readers, WCAG" 2>/dev/null
gh label create devops       --color "d4c5f9" --description "CI/CD, Docker, deployment, tooling" 2>/dev/null
gh label create documentation --color "0075ca" --description "Docs, README, guides, workflow" 2>/dev/null
gh label create performance  --color "fbca04" --description "Speed, caching, optimisation" 2>/dev/null
gh label create architecture --color "5319e7" --description "Code structure, design patterns, significant refactoring" 2>/dev/null
gh label create feature      --color "a2eeef" --description "Net-new user-facing capabilities" 2>/dev/null
gh label create production   --color "b60205" --description "Rate limiting, graceful shutdown, error reporting" 2>/dev/null
```

### Phase 4: Local Configuration

**Step 12: Detect test command**

Check in order:

1. **Taskfile.yml / Taskfile.yaml** — parse for a `test` task. If found → `task test`
2. **package.json** — check for `test` script in `scripts`. If found, detect package manager:
   - `pnpm-lock.yaml` exists → `pnpm test`
   - `yarn.lock` exists → `yarn test`
   - `bun.lockb` exists → `bun test`
   - otherwise → `npm test`
3. **go.mod** → `go test ./...`
4. **Cargo.toml** → `cargo test`
5. **pyproject.toml** → `uv run pytest`
6. **Nothing found** — ask the user: "Could not detect test command. What command runs your tests?"

**Step 13: Create .claude/ directory**

```bash
mkdir -p .claude
```

**Step 14: Write or migrate .claude/project.json**

The `ship.autoMerge` policy is the only field in the `ship` block; it drives /ship's merge fork and the `enforce-merge-gate` hook. Whenever you are about to write that field (a fresh config, or a migration that lacks a `ship` block), ask the user first: "Should /ship merge automatically once a PR passes review and CI, or stop and wait for your explicit go-ahead? (auto / wait) [auto]". Default to `auto` on an empty answer. `auto` → `ship.autoMerge = true`; `wait` → `ship.autoMerge = false`.

Write the config, taking the branch that matches the repo's current state:

- **No `.claude/project.json` yet:** Read the template from `${CLAUDE_SKILL_DIR}/templates/project.json`. Substitute all placeholders with the actual values captured during setup (owner, repo, repository node ID, project number/node ID, all field IDs, all option IDs, test command), and set `ship.autoMerge` to the answer above (the template ships `true` as the default). `project.number` must be written as a number, not a string. Write the result to `.claude/project.json`.
- **`.claude/project.json` already exists (adoption / migration):** Do NOT overwrite it — its captured IDs are live and re-capturing them is unnecessary. Read it and add only the keys it is missing. A config written before v4 has no `ship` block: add `"ship": {"autoMerge": <answer>}` (asking the auto-merge question only in this case) and leave every existing key exactly as it was. If a `ship` block is already present, leave it untouched and ask nothing. This is a migration, never a replacement — merging in the missing keys is what keeps re-running safe on an already-configured repo.

**Step 15: Generate starter CLAUDE.md**

Only create if CLAUDE.md does not already exist. If it exists, skip with a message.

Read the template from `${CLAUDE_SKILL_DIR}/templates/CLAUDE.md`. Substitute `<projectNumber>`, `<owner>`, and `<testCommand>` with the actual values from the setup results. Write the result to `CLAUDE.md` in the repo root.

**Step 16: Update .gitignore**

Append `.claude/settings.local.json` to `.gitignore` if not already present:

```bash
grep -q 'settings.local.json' .gitignore 2>/dev/null || echo '.claude/settings.local.json' >> .gitignore
```

### Phase 5: Post-setup

**Step 17: Print summary**

```
Setup complete:
  Project: <owner>/<repo> Backlog (#<number>)
  Fields:  Status (5 options), Priority (5), Effort (5), Type (4)
  Labels:  12 created
  Config:  .claude/project.json
  Docs:    CLAUDE.md (starter)
  Test:    <test-command>

Files written (unstaged — review before committing):
  .claude/project.json
  CLAUDE.md
  .gitignore
```

**Step 18: Check global CLAUDE.md**

```bash
test -f ~/.claude/CLAUDE.md
```

If missing, print:
```
Note: No global ~/.claude/CLAUDE.md found. Consider creating one
for behavioral rules that apply across all your repos.
```

**Step 19: Offer an audit sweep (existing repos)**

When this run adopted an existing repo — one that already had code, not one you just created empty — offer to run `/audit` now with ingestion enabled:
```
This repo already has code. Run /audit to sweep it for gaps and harvest any
TODO/FIXME/ROADMAP intent onto the board? (y/n)
```
On yes, hand off to `/audit`. On no, note that `/audit` can be run at any time. Skip this offer entirely for a brand-new empty repo — there is nothing to sweep yet.

**Step 20: Leave files unstaged**

Do not commit. The user reviews first.

## Idempotency

Every step checks before creating:
1. Project exists → reuse (with confirmation)
2. Field exists → skip, capture ID
3. Label exists → skip
4. `.claude/` exists → skip mkdir
5. `project.json` exists → migrate in place — add only the keys it lacks (e.g. the `ship` block); never overwrite live captured IDs
6. `CLAUDE.md` exists → skip (never overwrite user content)
7. `.gitignore` entry exists → skip

## Error Recovery

If the skill fails partway through:
1. Re-running is safe due to idempotency
2. Partial GitHub Project state is fine — missing fields get created on re-run
3. Print what was completed and what failed so the user knows the state
