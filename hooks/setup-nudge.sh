#!/bin/bash
# Onboarding/discovery nudge at session start. NOT an enforcement hook: it never
# blocks anything. When a repo has a GitHub remote but is not (fully) configured
# for gh-pm, it injects one line of context offering /setup-project.
#
# Contract: read SessionStart JSON on stdin, emit a hookSpecificOutput JSON
# object on stdout ONLY in the two nudge cases, exit 0 in every path. Git-only
# checks, no network — SessionStart runs on every session and must stay fast.
# Fail-open: any unexpected state exits 0 silently; a broken nudge must never
# break session start. POSIX bracket classes only ([[:space:]], never \s) so it
# runs identically under macOS BSD grep and ugrep.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# Enter the session's working directory; fail open if it is not reachable.
cd "$CWD" 2>/dev/null || exit 0

# Silent unless this is a git repo with a GitHub remote.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
git remote -v 2>/dev/null | grep -qi 'github\.com' || exit 0

# Durable opt-out: the user declined and left a sentinel. Stay silent forever.
[ -f .claude/gh-pm-optout ] && exit 0

PROJECT_JSON=".claude/project.json"

# Nudge case 1 — unconfigured: has a GitHub remote but no project config yet.
if [ ! -f "$PROJECT_JSON" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: "gh-pm: this repo has a GitHub remote but no .claude/project.json, so it is not set up for gh-pm. Offer to run /setup-project to bootstrap the GitHub Project board and workflows. If the user would rather not, they can decline durably by creating an empty .claude/gh-pm-optout file."
    }
  }'
  exit 0
fi

# project.json exists. Malformed JSON → fail open, silent.
jq -e . "$PROJECT_JSON" >/dev/null 2>&1 || exit 0

# A valid config object that already carries the "ship" key is current-schema and
# fully configured → silent. A valid config object WITHOUT "ship" predates the
# current schema → nudge case 2. Anything that is not a JSON object → silent.
if jq -e 'type == "object" and (has("ship") | not)' "$PROJECT_JSON" >/dev/null 2>&1; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: "gh-pm: .claude/project.json exists but predates the current config schema (missing the \"ship\" key). Offer to run /setup-project to migrate it non-destructively to the current schema."
    }
  }'
  exit 0
fi

exit 0
