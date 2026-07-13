#!/bin/bash
# Block `git commit` on the default branch (allow --amend).
#
# Contract: read tool-call JSON on stdin, emit a hookSpecificOutput JSON object
# on stdout to deny/ask, exit 0 in every path. POSIX bracket classes only
# ([[:space:]], never \s) — must run identically under macOS BSD grep and ugrep.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

# Strip quoted spans before scanning for flags so tokens inside the commit message
# (git commit -m "do not --amend published commits") are treated as prose, not as
# --amend/-C/--git-dir flags. A real flag must sit OUTSIDE quotes to function.
# Single-quoted spans removed first, then double-quoted — portable BSD/GNU sed.
SANITIZED=$(echo "$COMMAND" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')

# Split the sanitized line into top-level segments on ; && || | & and newline, so
# an --amend in one segment cannot exempt a real commit in another (a line-global
# --amend match would let `git commit -m real; echo --amend` slip through), and a
# pipeline like `git log | grep commit` is not mistaken for a commit. `&&`/`||`
# split into an extra empty segment, which is harmless.
#
# A segment is a commit invocation when it contains `git` … `commit` non-adjacently
# (so `git -C DIR commit`/`git -c k=v commit` still count). REAL_COMMIT is set when
# at least one commit segment is NOT an --amend; only then does the branch check
# apply. --amen is the shortest unambiguous prefix of --amend for git commit, so
# match from there onward.
SEGMENTS=$(echo "$SANITIZED" | tr ';&|' '\n')
REAL_COMMIT=0
while IFS= read -r SEG; do
  echo "$SEG" | grep -qE '\bgit\b.*\bcommit\b' || continue
  echo "$SEG" | grep -qE '\-\-amen' && continue
  REAL_COMMIT=1
done <<< "$SEGMENTS"

# No real (non-amend) commit segment → nothing to guard, allow.
[ "$REAL_COMMIT" -eq 1 ] || exit 0

# Directory/repo-redirecting invocations make the operation target a repo other
# than $CWD, so the $CWD-based branch check below cannot be trusted — ask instead
# of guessing. --git-dir and --work-tree are top-level-only, so match them
# anywhere; -C is matched only when it precedes the commit subcommand (commit's
# own `-C <commit>` reuse-message flag stays in $CWD and must not trigger this).
if echo "$SANITIZED" | grep -qE '\-\-git-dir|\-\-work-tree' \
  || echo "$SANITIZED" | grep -qE '(^|[[:space:]])-C[[:space:]].*\bcommit\b'; then
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

# Already on the default branch → deny the direct commit.
if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "deny",\n    "permissionDecisionReason": "Cannot commit directly to %s. Create a feature branch first."\n  }\n}\n' "$DEFAULT_BRANCH"
  exit 0
fi

# On a feature branch, but the same line switches/checks out the default branch
# before committing — the eval-time branch cannot be trusted, so ask. Match
# `git switch|checkout [-c|-b] <name>` for the detected default plus literal
# main/master. \b is already used elsewhere in this hook and is portable here.
SWITCH_ALT="main|master"
if [ "$DEFAULT_BRANCH" != "main" ] && [ "$DEFAULT_BRANCH" != "master" ]; then
  SWITCH_ALT="$DEFAULT_BRANCH|$SWITCH_ALT"
fi
if echo "$SANITIZED" | grep -qE "\bgit\b[[:space:]]+(switch|checkout)[[:space:]]+((-c|-b)[[:space:]]+)?($SWITCH_ALT)\b"; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "This command switches to the default branch before committing, so the current-branch check is unreliable. Confirm this commit is not to a default branch."
  }
}
EOF
  exit 0
fi

# Feature branch, no switch to the default branch → allow.
exit 0
