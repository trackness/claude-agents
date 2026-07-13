#!/bin/bash
# Deny attempts to bypass git hooks (--no-verify in any form, or a core.hooksPath
# override) on any git command.
#
# Contract: read tool-call JSON on stdin, deny via a hookSpecificOutput JSON
# object on stdout, exit 0 in every path. POSIX bracket classes only ([[:space:]],
# never \s) — the hook must run identically under macOS BSD grep and ugrep.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Strip quoted spans before scanning for bypass flags. A real --no-verify/-n must
# sit OUTSIDE quotes to function as a flag; a token inside the commit message
# (git commit -m "explain --no-verify") is prose, not a flag, and must not deny.
# Single-quoted spans removed first, then double-quoted — portable BSD/GNU sed.
SANITIZED=$(echo "$COMMAND" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')

# Gate on the git verb itself, not `git <subcommand>` adjacency. Flags may sit
# between `git` and the subcommand (`git -C DIR commit`, `git -c k=v commit`), so
# subcommand-adjacent gating skips those invocations.
echo "$COMMAND" | grep -qE '\bgit\b' || exit 0

# Deny --no-verify in any abbreviated long-option form. git resolves any
# unambiguous prefix of a long option; --no-veri is the shortest prefix that
# resolves to --no-verify (--no-verbose diverges at the next character), so
# matching from --no-veri onward covers --no-veri, --no-verif, --no-verify while
# leaving --no-verbose alone.
if echo "$SANITIZED" | grep -qE '\-\-no-veri'; then
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

# Deny a per-command core.hooksPath override: git -c core.hooksPath=... or
# --config core.hooksPath=... (with or without whitespace after -c/--config,
# including the no-space -ccore.hooksPath= form). Pointing hooksPath elsewhere
# (e.g. /dev/null) disables every git hook — the same bypass class as
# --no-verify. Matched case-insensitively because git config keys are
# case-insensitive (core.hookspath, CORE.HooksPath, ...). The required trailing
# `core.hooksPath=` keeps this from firing on a plain `-C <dir>`.
if echo "$SANITIZED" | grep -qiE '(^|[[:space:]])(-c|--config)[[:space:]]*core\.hooksPath='; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Overriding core.hooksPath to bypass git hooks is forbidden. Fix the hook failure instead of bypassing it."
  }
}
EOF
  exit 0
fi

# Split the line into top-level segments on ; && || | & and newline, then scan
# each for the remaining per-segment bypasses.
SEGMENTS=$(echo "$SANITIZED" | tr ';&|' '\n')
DENY_HOOKSPATH=0
DENY_N=0
while IFS= read -r SEG; do
  # Persistent set of core.hooksPath: `git config [--global|--local|...]
  # core.hooksPath <path>` writes the key into config so every later commit skips
  # hooks — same bypass class as --no-verify. Case-insensitive (config keys are);
  # require whitespace + a value after the key so a pure read
  # (`git config --get core.hooksPath`, key with no following value) still passes.
  # Checked per segment so a read followed by `&& ...` is not read as a value.
  if echo "$SEG" | grep -qiE '\bgit\b[[:space:]]+config\b.*core\.hooksPath[[:space:]]+[^[:space:]]'; then
    DENY_HOOKSPATH=1
    break
  fi
  # Deny -n (--no-verify) bundled into a short-flag cluster on a commit (-n, -an,
  # -na, -anm, ...). Scoped to the commit segment: on `git push -n` (--dry-run) or
  # `git clean -n` the -n is legitimate and must pass, even when a separate commit
  # segment shares the line.
  echo "$SEG" | grep -qE '\bgit\b.*\bcommit\b' || continue
  if echo "$SEG" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
    DENY_N=1
    break
  fi
done <<< "$SEGMENTS"

if [ "$DENY_HOOKSPATH" -eq 1 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Overriding core.hooksPath to bypass git hooks is forbidden. Fix the hook failure instead of bypassing it."
  }
}
EOF
  exit 0
fi

if [ "$DENY_N" -eq 1 ]; then
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

exit 0
