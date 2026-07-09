#!/bin/bash
# Deny attempts to bypass git hooks (--no-verify in any form) on any git command.
#
# Contract: read tool-call JSON on stdin, deny via a hookSpecificOutput JSON
# object on stdout, exit 0 in every path. POSIX bracket classes only ([[:space:]],
# never \s) — the hook must run identically under macOS BSD grep and ugrep.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Gate on the git verb itself, not `git <subcommand>` adjacency. Flags may sit
# between `git` and the subcommand (`git -C DIR commit`, `git -c k=v commit`), so
# subcommand-adjacent gating skips those invocations.
echo "$COMMAND" | grep -qE '\bgit\b' || exit 0

# Deny --no-verify in any abbreviated long-option form. git resolves any
# unambiguous prefix of a long option; --no-veri is the shortest prefix that
# resolves to --no-verify (--no-verbose diverges at the next character), so
# matching from --no-veri onward covers --no-veri, --no-verif, --no-verify while
# leaving --no-verbose alone.
if echo "$COMMAND" | grep -qE '\-\-no-veri'; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "--no-verify is forbidden. Fix the hook failure instead of bypassing it."
  }
}
EOF
  exit 0
fi

# Deny -n (--no-verify) bundled into a short-flag cluster on a commit (-n, -an,
# -na, -anm, ...). Scoped to commit only: on `git push` the -n short flag is
# --dry-run and must pass, so require both `git` and `commit` to be present.
if echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' \
  && echo "$COMMAND" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "-n (--no-verify) is forbidden. Fix the hook failure instead of bypassing it."
  }
}
EOF
fi
