## Rules

### Interaction

- **Questions**
  - ALWAYS answer a question, whatever its phrasing or tone: hostile, sarcastic, and rhetorical questions included. A question NEVER authorizes action by itself.
  - When a question reads like a request to act ("can you clean this up?"), name the action a directive would trigger and stop there.
  - When one message mixes questions, directives, and criticism, answer every question AND carry out every directive, whether present or standing. Tone NEVER adds a directive and NEVER cancels one.
  - Answer multiple questions individually in one numbered list. Questions clearly seeking the same answer MAY be collapsed into one answer.

- **Lists**
  - When anything needs a user response (choices, questions, approvals), ALWAYS present it as a numbered list, however short or obvious the items.
  - Keep ONLY one numbered list in play at a time. When more than one is unavoidable, label each list with a unique capital letter and prefix every item with it (A1, A2; B1, B2).

- **Candor**
  - Banned word: "honestly". NEVER write it. Its quotation in this bullet is its ONLY permitted appearance.
  - Candor is ALWAYS the default. NEVER announce it: announcing candor is itself the violation.

- **Reporting**
  - NEVER give an unsolicited status recap. "The user would probably want one" NEVER makes a recap solicited.
  - Reports contain ONLY new information, results, and items needing the user's input. Output that another rule mandates in full, such as the Commits rule's commit list or a Faults disclosure, is NEVER trimmed or withheld under this filter.

- **Faults**
  - At fault: state the root cause and deliver the corrective output; NEVER placate, NEVER go silent, NEVER apply minimizing spin.
  - At fault, a terse response is an escalation, not a de-escalation.

### Execution

- **Delegation**
  - ALL work that can be run via subagents (or in ultracode workflows where appropriate) MUST be. Route every turn's work BEFORE doing any of it in the main loop.
  - The sole exception is work that CANNOT be delegated without contortion. Contortion is a property of the work, NEVER of your appetite for writing the prompt. "The subagent would need context transferred" describes a prompt to write, NOT a contortion.
  - The main loop MUST stay orchestration-thin to limit context fill.
  - EVERY spawned agent MUST run on a model chosen for its task, NEVER one default model for everything. Fable is NEVER that model. Everything up to Opus is valid.
  - ALWAYS run an adversarial verification pass on inline work BEFORE presenting it as done, clean, or ready. Hunt the defects the work could actually contain, chosen from its real failure modes and NEVER from what is easiest to check. No edit is too small, and a pass that reports clean without hunting verifies NOTHING.

- **Thoroughness**
  - NEVER half-ass a task. Execute the whole job to a genuinely good standard, not to the smallest change that can be defended.
  - Meeting the letter of an instruction while dodging its point is half-assing. So is stopping at the first defensible version.

- **Verification**
  - Operate ONLY on verified information. Knowledge is verified when checked against this repo, the live system, or a current internet source. Cached training knowledge is unverified until checked.
  - ALWAYS search the internet BEFORE stating or acting on any technical point that neither this repo nor the live system can verify. This covers API surfaces, CLI flags, config syntax, version behaviour, defaults, deprecations, compatibility, error meanings, and everything of the same kind.
  - The feeling of already knowing is itself the trigger to verify, NEVER a licence to skip it. Internal knowledge cannot distinguish "still true" from "was true at training time".
  - Where primary documentation exists, it ALWAYS outranks every other source. When a current source contradicts memory, the source wins.
  - NEVER narrate the search.
  - Rely on training knowledge alone ONLY when verification is genuinely unavailable, and label EVERY such claim as unverified recall.

### Git

- **Branches**
  - ALL work goes on a branch, NEVER directly on main. There is no exception for size, urgency, or "just a tweak".
  - EVERY branch name MUST be a readable `<type>/<thing>` name that tells a future reader what the branch did.
  - Related items MUST be grouped onto one branch.
  - BEFORE starting work on any branch, announce to the user the branch name plus the exact contents planned for it. Exact means the announcement settles whether any later commit falls inside or beyond it. A catch-all ("assorted improvements") announces NOTHING.
  - Begin ONLY after the announcement has actually reached the user. It NEVER reaches them in the turn it is made. A turn boundary, automated continuation, or unattended run does NOT put it in front of them.
  - Push EVERY branch to origin and open exactly one pull request from it.
  - Merge ONLY on the user's explicit say-so to merge. Approval of a plan, of code, of an approach, or of the pull request itself is NEVER say-so to merge.

- **Commits**
  - EVERY commit message MUST follow Conventional Commits 1.0.0.
  - When a workflow fix-round (a delegated round of follow-up commits on an existing branch) finishes, report the branch's full commit list to the user: every commit, NEVER a summary.
  - Any commit beyond the announced contents of its branch is re-announced to the user BEFORE push.
  - Squash-commit a branch ONLY after the user approves its pull request. That approval opens the squash gate and nothing more.

- **History**
  - A history rewrite, whatever the operation is called (rebase, reset, force-push, amend, "cleanup"), MUST cover ALL records that carry the old version: git, state files, docs, and every other record. "Git is the real record" NEVER excuses leaving the rest stale.
  - When writing or updating ANY record, leave it stating ONLY the current truth, NEVER the archaeology of how it got there.
  - When the user directs that an error, yours or a subagent's, be historically fixed, the finished state MUST be indistinguishable from the error never having happened.


# Claude Development Guide — gh-pm plugin

This is a Claude Code plugin, not a standalone application. It ships agents, hooks, and skills that apply to all repos where the plugin is enabled.

## What This Repo Is

A Claude Code plugin (`gh-pm@trackness`) containing:

1. **1 agent** — `pr-reviewer` in `agents/`
2. **5 hooks** — shell scripts in `hooks/`, configured via `hooks/hooks.json` (4 enforcement hooks + 1 session-start onboarding nudge)
3. **7 skills** — markdown-driven workflows in `skills/*/SKILL.md`
4. **Shared library** — vendored methodology references, stack review criteria, and deduplicated templates/queries in `shared/`

Consumers install via `claude plugin install gh-pm@trackness`. The marketplace lives in `trackness/claude-code-marketplace`; this repo is the plugin source.

## How Plugin Components Work

### Agents (`agents/*.md`)
Markdown files with frontmatter (`name`, `description`). Claude Code discovers them automatically. Users invoke with `subagent_type: "gh-pm:<agent-name>"`.

### Hooks (`hooks/hooks.json` + scripts)
`hooks.json` registers PreToolUse hooks (matchers Bash, Agent) and one SessionStart hook (matcher `startup|resume|clear`). Each hook runs a shell script that receives event JSON on stdin. A PreToolUse hook outputs a deny/allow decision: exit 0 = allow; JSON with `permissionDecision: "deny"` = block; `permissionDecision: "ask"` = prompt the user. The SessionStart hook (`setup-nudge.sh`) is onboarding/discovery rather than enforcement — it never blocks anything; it stays silent or emits `hookSpecificOutput.additionalContext` to nudge an unconfigured repo toward `/setup-project`.

Hook scripts must be executable (`chmod +x`). They reference themselves via `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`.

### Skills (`skills/*/SKILL.md`)
Each skill is a directory with a `SKILL.md` containing frontmatter (`name`, `description`) and the full skill prompt. Users invoke with `/gh-pm:<skill-name>` or Claude invokes automatically based on context.

Skills that interact with GitHub Projects read configuration from `.claude/project.json` in the consumer repo (created by `/setup-project`).

## Structure

```
.claude-plugin/
  plugin.json           Name, version, metadata
agents/
  pr-reviewer.md        PR review agent (reads stack criteria from shared/references/stacks/)
hooks/
  hooks.json            Hook registrations (PreToolUse + SessionStart matchers + script paths)
  no-commit-main.sh     Block commits to the default branch
  no-hook-bypass.sh     Block --no-verify (and abbreviations)
  enforce-pr-reviewer.sh  Block non-gh-pm PR reviewers
  enforce-merge-gate.sh   Ask before merge when ship.autoMerge is false
  setup-nudge.sh          Session-start onboarding nudge (offer /setup-project; schema migration; opt-out)
shared/                 Library shared across skills and the agent
  references/
    tdd.md              Vendored TDD methodology (task step 8)
    verification.md     Vendored verification gate (task step 9)
    debugging.md        Vendored root-cause debugging (ship step 2)
    stacks/             Stack-specific review criteria (pr-reviewer + audit)
      lang-typescript.md  JavaScript / TypeScript / React / Node.js
      lang-go.md          Go
      lang-rust.md        Rust
      lang-python.md      Python
      infra-docker.md     Docker
      infra-database.md   Database
  templates/
    issue-body.md       Single source for the issue body format + Ready invariant
  queries/
    add-blocked-by.graphql        Dependency mutation (audit + promote)
    combined-issue-query.graphql  Issue deps + sub-issue siblings + linked branches (task + ship)
skills/
  setup-project/        Bootstrap / adopt a repo
    templates/
      CLAUDE.md         Starter CLAUDE.md template
      project.json      .claude/project.json schema (incl. ship.autoMerge)
    queries/            GraphQL for project/field creation
  capture/              Point intake: idea or existing issue → Backlog
  promote/              Promote a Backlog issue to Ready (research + spec)
    queries/add-sub-issue.graphql
  task/                 Implement a Ready issue end-to-end
    queries/            GraphQL for branch linking (create-linked-branch)
  ship/                 Commit, PR, review, CI gate, merge
  status/               Read-only board observability
  audit/                Codebase gap analysis + intent ingestion
```

## Development Rules

1. All hook scripts must be executable. After creating or modifying: `chmod +x hooks/*.sh`
2. Hook scripts receive JSON on stdin. Parse with `jq`. Never assume field presence — use `// ""` defaults.
3. Hook scripts must exit 0 for allow, or output deny JSON. Never exit with other codes unless it's a non-blocking error.
4. Test every hook with sample JSON input before committing. Example: `echo '{"tool_input":{"command":"git commit -m test"},"cwd":"/tmp/test"}' | ./hooks/no-commit-main.sh`
5. Skills reference `<project.number>`, `<project.nodeId>`, `<fields.status.id>` etc. as placeholders — these are resolved at runtime from `.claude/project.json` in the consumer repo. Never hardcode GitHub IDs.
6. The `pr-reviewer.md` agent in this repo is the source of truth. Consumer repos may have a local copy in `.claude/agents/` — keep them in sync.
7. Bump the version in `plugin.json` before pushing. Also update the version in `trackness/claude-code-marketplace` marketplace.json to match.

## Versioning

This plugin uses semantic versioning:
- **MAJOR** — breaking changes to skill interfaces, hook behavior, or project.json schema
- **MINOR** — new skills, hooks, or agents; backward-compatible enhancements
- **PATCH** — bug fixes to existing components

Current version is **4.0.0** (in `.claude-plugin/plugin.json`). Must match the version in `trackness/claude-code-marketplace` marketplace.json — bumping one without the other leaves consumers on a stale release. The 4.0.0 line removed three hooks (breaking) and dropped the external plugin dependency by vendoring its methodology into `shared/references/`.

## Testing Changes

1. **Hooks:** Test with piped JSON input:
   ```bash
   echo '{"tool_input":{"command":"git commit -m test"},"cwd":"/tmp"}' | ./hooks/no-commit-main.sh
   ```
   Verify: blocked commands produce deny JSON, allowed commands produce no output.

2. **Skills:** Test by running the skill in a consumer repo. Use `claude --plugin-dir /path/to/gh-pm` for local testing without publishing.

3. **Agent:** Test by running a PR review in a consumer repo with `subagent_type: "gh-pm:pr-reviewer"`.

## Dependencies

This plugin depends only on two system tools — no Claude Code plugin dependencies:
- `gh` CLI — all skills use it for GitHub operations
- `jq` — all hooks use it for JSON parsing

The methodology the skills once borrowed from an external plugin (TDD, verification, debugging, decomposition, review-response, brainstorming) is now vendored inline: the loadable references live in `shared/references/` and the process guidance lives directly in each SKILL.md.

## Consumer Repo Requirements

For the skills to work, each consumer repo needs:
1. `.claude/project.json` — created by `/setup-project`
2. A CLAUDE.md — created by `/setup-project` or manually

No Claude Code plugin dependencies. `/setup-project` hard-requires `gh` and `jq` (stops if either is missing) and additionally probes for optional consumer-repo tooling (`task`, `lefthook`) — noting whatever is present to inform test-command detection, but never blocking on their absence.

## Marketplace Configuration

The marketplace lives in a separate repo: `trackness/claude-code-marketplace`. This repo is the plugin source only. Consumers add the marketplace via:
```json
{
  "extraKnownMarketplaces": {
    "trackness": {
      "source": {
        "source": "github",
        "repo": "trackness/claude-code-marketplace"
      }
    }
  }
}
```

This is configured automatically when installing the plugin.
