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

# Only inspect `gh pr merge`. Whitespace-tolerant so extra spaces
# (`gh  pr  merge`) cannot slip past.
echo "$COMMAND" | grep -qE '\bgh\b[[:space:]]+pr[[:space:]]+merge\b' || exit 0

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
