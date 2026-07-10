#!/bin/bash
# Ask before `gh pr merge` when the consumer repo has opted out of auto-merge
# (.claude/project.json -> ship.autoMerge == false).
#
# Contract: read tool-call JSON on stdin, emit a hookSpecificOutput JSON object
# on stdout to ask, exit 0 in every path. POSIX bracket classes only
# ([[:space:]], never \s) -- must run identically under macOS BSD grep and ugrep.
#
# Fail-open by design: the gate is opt-in. Only an explicit ship.autoMerge=false
# raises the prompt. A missing key, an absent file, a true value, or an
# unparseable file all pass through silently.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

# Only inspect an actual `gh pr merge` invocation. `gh` must sit at a command
# position -- string start or just after a shell separator (; & | ( newline),
# optionally behind one or more launcher builtins (sudo/env/time/command/xargs/
# nice/nohup) -- so the pattern still fires on `sudo gh pr merge` yet cannot fire
# on the substring "gh pr merge" buried in a quoted argument such as a commit
# message. Whitespace-tolerant (`gh  pr  merge`), and `merge` must end at a word
# boundary so `merge-queue` and the like do not match.
echo "$COMMAND" | grep -qE '(^|[;&|(])[[:space:]]*((sudo|env|time|command|xargs|nice|nohup)[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' || exit 0

# No config file, no gate.
PROJECT_JSON="$CWD/.claude/project.json"
[ -f "$PROJECT_JSON" ] || exit 0

# Read ship.autoMerge. Only the explicit boolean false raises the prompt:
# "true" and "null" (key absent) fall through, and an unparseable file makes jq
# fail with empty output -- also a fall-through.
AUTO_MERGE=$(jq -r '.ship.autoMerge' "$PROJECT_JSON" 2>/dev/null)
if [ "$AUTO_MERGE" = "false" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "ship.autoMerge is false in .claude/project.json, so merging requires explicit human say-so. Approval of a plan, code, an approach, or the PR itself is not say-so to merge. Confirm you intend to merge this PR now."
  }
}
EOF
fi

exit 0
