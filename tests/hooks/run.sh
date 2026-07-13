#!/bin/bash
# Regression harness for the gh-pm PreToolUse enforcement hooks.
#
# For each case it pipes a tool-call JSON through the target hook and asserts the
# decision: deny / ask / allow (allow == empty stdout). Branch-context cases need
# real git state, so the runner builds throwaway temp repos — one on the default
# branch (main), one on a feature branch — each with refs/remotes/origin/HEAD set
# to main so the hook's default-branch detection resolves without a network call.
#
# Deps: bash + jq + git only. Exits non-zero if any case fails.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
HOOKS="$REPO_ROOT/hooks"

# Hermetic git: ignore the developer's global/system config (hooksPath, signing,
# user identity) so the harness behaves identically on any machine and on CI.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gh-pm-hooktests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

TOTAL=0
FAILED=0

# Build a git repo with an initial commit and origin/HEAD -> main. Ends on the
# default branch (main), or on a `feature` branch when $2 is "feature".
build_repo() {
  dir="$1"
  git -c init.defaultBranch=main init -q "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "gh-pm tests"
  git -C "$dir" commit -q --allow-empty -m init
  git -C "$dir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  if [ "${2:-}" = "feature" ]; then
    git -C "$dir" checkout -q -b feature
  fi
}

# Build a git repo carrying .claude/project.json with ship.autoMerge = $2, plus an
# empty sub/ directory to exercise the subdirectory-resolution path.
build_merge_repo() {
  dir="$1"
  git -c init.defaultBranch=main init -q "$dir"
  mkdir -p "$dir/.claude" "$dir/sub"
  printf '{"ship":{"autoMerge":%s}}\n' "$2" > "$dir/.claude/project.json"
}

MAIN_REPO="$TMP/main-repo"
FEATURE_REPO="$TMP/feature-repo"
MERGE_FALSE="$TMP/merge-false"
MERGE_TRUE="$TMP/merge-true"
MERGE_NONE="$TMP/merge-none"

build_repo "$MAIN_REPO"
build_repo "$FEATURE_REPO" feature
build_merge_repo "$MERGE_FALSE" false
build_merge_repo "$MERGE_TRUE" true
git -c init.defaultBranch=main init -q "$MERGE_NONE"

# run_case <hook.sh> <expected: deny|ask|allow> <cwd> <command>
run_case() {
  hook="$1"; expected="$2"; cwd="$3"; cmd="$4"
  input=$(jq -n --arg c "$cmd" --arg d "$cwd" '{tool_input:{command:$c},cwd:$d}')
  out=$(printf '%s' "$input" | "$HOOKS/$hook")
  if [ -z "$out" ]; then
    decision="allow"
  else
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "PARSE_ERROR"' 2>/dev/null)
    [ -n "$decision" ] || decision="PARSE_ERROR"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$decision" = "$expected" ]; then
    printf 'PASS  %-20s expect=%-5s  %s\n' "$hook" "$expected" "$cmd"
  else
    printf 'FAIL  %-20s expect=%-5s got=%-5s  %s\n' "$hook" "$expected" "$decision" "$cmd"
    FAILED=$((FAILED + 1))
  fi
}

echo "== no-commit-main.sh =="
run_case no-commit-main.sh deny  "$MAIN_REPO"    'git commit -m real'
run_case no-commit-main.sh allow "$MAIN_REPO"    'git commit --amend'
run_case no-commit-main.sh deny  "$MAIN_REPO"    'git commit -m real; echo --amend'          # F2
run_case no-commit-main.sh deny  "$MAIN_REPO"    'git commit -m "do not --amend this"'        # quoted --amend != exempt
run_case no-commit-main.sh ask   "$FEATURE_REPO" 'git switch main && git commit -m x'         # F3
run_case no-commit-main.sh deny  "$MAIN_REPO"    'git switch main && git commit -m x'         # already on default -> deny wins
run_case no-commit-main.sh ask   "$MAIN_REPO"    'git -C /other/repo commit -m x'
run_case no-commit-main.sh allow "$FEATURE_REPO" 'git commit -m x'
run_case no-commit-main.sh allow "$MAIN_REPO"    'echo hello'
run_case no-commit-main.sh allow "$MAIN_REPO"    'git log | grep commit'                      # pipeline, not a commit

echo "== no-hook-bypass.sh =="
run_case no-hook-bypass.sh deny  "$TMP" 'git commit --no-verify -m x'
run_case no-hook-bypass.sh deny  "$TMP" 'git -c core.hooksPath=/dev/null commit -m x'         # F4
run_case no-hook-bypass.sh deny  "$TMP" 'git -ccore.hooksPath=/dev/null commit -m x'          # F4 no-space form
run_case no-hook-bypass.sh deny  "$TMP" 'git --config core.hooksPath=/dev/null commit -m x'   # F4 long form
run_case no-hook-bypass.sh deny  "$TMP" 'git -c core.hookspath=/dev/null commit -m x'         # F4 lowercase key
run_case no-hook-bypass.sh deny  "$TMP" 'git -c CORE.HooksPath=/dev/null commit -m x'         # F4 mixed case
run_case no-hook-bypass.sh deny  "$TMP" 'git config core.hooksPath /dev/null && git commit -m x'  # F4 persistent set
run_case no-hook-bypass.sh allow "$TMP" 'git config --get core.hooksPath'                     # F4 read must pass
run_case no-hook-bypass.sh deny  "$TMP" 'git commit -nm x'
run_case no-hook-bypass.sh deny  "$TMP" 'git commit -an -m x'
run_case no-hook-bypass.sh allow "$TMP" 'git commit -m x && git clean -n'                     # F20
run_case no-hook-bypass.sh allow "$TMP" 'git commit -m x'
run_case no-hook-bypass.sh allow "$TMP" 'git push -n'
run_case no-hook-bypass.sh allow "$TMP" 'git clean -n'

echo "== enforce-merge-gate.sh =="
run_case enforce-merge-gate.sh ask   "$MERGE_FALSE"     'gh pr merge 12 --squash'
run_case enforce-merge-gate.sh ask   "$MERGE_FALSE/sub" 'gh pr merge 12 --squash'             # F5 (subdir)
run_case enforce-merge-gate.sh allow "$MERGE_TRUE"      'gh pr merge 12 --squash'
run_case enforce-merge-gate.sh allow "$MERGE_NONE"      'gh pr merge 12 --squash'
run_case enforce-merge-gate.sh allow "$MERGE_FALSE"     'gh pr view 12'                        # gate only fires on `pr merge`

echo
if [ "$FAILED" -eq 0 ]; then
  printf 'All %d cases passed.\n' "$TOTAL"
  exit 0
else
  printf '%d of %d cases FAILED.\n' "$FAILED" "$TOTAL"
  exit 1
fi
