#!/bin/bash
# Block `git commit` on the default branch (allow --amend).
#
# Contract: read tool-call JSON on stdin, emit a hookSpecificOutput JSON object
# on stdout to deny/ask, exit 0 in every path. POSIX bracket classes only
# ([[:space:]], never \s) — must run identically under macOS BSD grep and ugrep.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

# Gate on git + commit non-adjacently so flags between them (`git -C DIR commit`,
# `git -c k=v commit`) are still inspected.
echo "$COMMAND" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

# Allow --amend in any abbreviated form. --amen is the shortest unambiguous prefix
# of --amend for git commit, so match from there onward.
echo "$COMMAND" | grep -qE '\-\-amen' && exit 0

# Directory/repo-redirecting invocations make the operation target a repo other
# than $CWD, so the $CWD-based branch check below cannot be trusted — ask instead
# of guessing. --git-dir and --work-tree are top-level-only, so match them
# anywhere; -C is matched only when it precedes the commit subcommand (commit's
# own `-C <commit>` reuse-message flag stays in $CWD and must not trigger this).
if echo "$COMMAND" | grep -qE '\-\-git-dir|\-\-work-tree' \
  || echo "$COMMAND" | grep -qE '(^|[[:space:]])-C[[:space:]].*\bcommit\b'; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "This git command targets a directory or repo other than the working directory (-C/--git-dir/--work-tree), so the current-branch check is unreliable. Confirm this commit is not to a default branch."
  }
}
EOF
  exit 0
fi

# Check current branch — fail closed if we can't determine it
if [ -z "$CWD" ]; then
  BRANCH=""
else
  BRANCH=$(cd "$CWD" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

if [ -z "$BRANCH" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Could not determine current branch. Confirm this commit is safe."
  }
}
EOF
  exit 0
fi

# Detect the default branch
DEFAULT_BRANCH=""
if [ -n "$CWD" ]; then
  DEFAULT_BRANCH=$(cd "$CWD" 2>/dev/null && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH=$(cd "$CWD" 2>/dev/null && gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
  fi
fi

# Fall back to main/master if detection fails
if [ -z "$DEFAULT_BRANCH" ]; then
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    DEFAULT_BRANCH="$BRANCH"
  else
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Could not detect the default branch. Confirm this commit is not to the default branch."
  }
}
EOF
    exit 0
  fi
fi

if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "deny",\n    "permissionDecisionReason": "Cannot commit directly to %s. Create a feature branch first."\n  }\n}\n' "$DEFAULT_BRANCH"
fi
