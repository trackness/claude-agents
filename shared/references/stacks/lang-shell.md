# Shell / Bash Review Criteria

## Strict Mode & Shell Options

- Scripts should start with `set -euo pipefail` (or justify each omission) — unset variables, failed commands, and broken pipes must not pass silently
- `set -e` has sharp edges — it is suppressed inside `if`/`while` conditions, `&&`/`||` chains, and command substitution; don't rely on it to catch errors in those positions
- Set `IFS=$'\n\t'` when default word-splitting on spaces is a hazard, or scope IFS changes locally
- Pin the interpreter with a correct shebang (`#!/usr/bin/env bash` for bash features; `#!/bin/sh` only for POSIX-portable scripts) — `[[ ]]`, arrays, and `local` are bashisms that break under `sh`/`dash`
- `set -x` and stray `echo`-based debugging must not be left in committed scripts

## Quoting & Expansion

- Every expansion that can contain spaces or globs must be double-quoted: `"$var"`, `"${arr[@]}"`, `"$(cmd)"` — unquoted expansions word-split and glob-expand
- Forward arguments with `"$@"` (quoted), never `$*` or unquoted `$@`
- Use `"${var}"` braces when the name is adjacent to other characters, and `"${var:-default}"` / `"${var:?message}"` for defaults and required-variable assertions
- Beware globbing in unquoted contexts (`rm $files`) and in `[ ]` tests — an empty or space-containing value silently changes the command's meaning

## Tests & Conditionals

- Prefer `[[ ]]` over `[ ]`/`test` in bash — `[[ ]]` does not word-split or glob its operands and supports `&&`, `||`, and `=~`
- Use `-n`/`-z` for string emptiness and quote the operand; numeric comparisons use `-eq`/`-lt`/… inside `[[ ]]`, or `(( ))`
- Arithmetic belongs in `(( ))` or `$(( ))`, not string comparison
- `[[ $x =~ regex ]]` — the right-hand side must be unquoted to be treated as a regex; anchor and escape it deliberately

## Command Substitution & Pipelines

- Use `$(...)`, not backticks — backticks don't nest and mangle escaping
- Word-splitting of unquoted command substitution is a top source of bugs — quote it unless splitting is intended
- A pipeline's exit status is its last command's unless `pipefail` is set — check `PIPESTATUS`/`pipefail` when an upstream failure must fail the script
- `while read` loops fed by a pipe run in a subshell — variables set inside are lost after the pipe; prefer process substitution: `while read ...; do ...; done < <(cmd)`
- Read lines safely with `IFS= read -r line` — bare `read` strips backslashes and leading/trailing whitespace

## Functions & Variables

- Declare function-local variables with `local` — un-`local`ed assignments leak into global scope and clobber callers
- Split declaration and assignment when you need the command's exit status: `local var; var=$(cmd)`. Combined `local var=$(cmd)` masks it, because the `local` builtin succeeds regardless of the substitution's status
- Prefer explicit `return`/exit codes over relying on the last command's status
- Avoid global mutable state shared across functions; pass inputs as arguments

## Cleanup, Traps & Temp Files

- Create temp files/dirs with `mktemp` — never a fixed `/tmp/name`, whose predictable path is a symlink-attack and collision hazard
- Register cleanup with `trap 'rm -rf "$tmp"' EXIT` immediately after creating the resource, so it is removed on every exit path including error
- Be explicit about which signals a trap covers (`EXIT`, `INT`, `TERM`); an `EXIT` trap already fires on both normal and errored exits
- Quote paths in cleanup commands — an unquoted or empty variable in `rm -rf $dir` is catastrophic

## Exit Codes & Error Handling

- Use meaningful, non-zero exit codes for distinct failure modes; reserve `0` for success
- Check the status of commands whose failure matters — let `set -e` catch it, test `$?` immediately, or guard with `|| { echo ...; exit 1; }`
- Emit diagnostics to stderr (`>&2`) so stdout stays parseable by callers
- Validate required arguments and environment up front; fail fast with a clear message rather than proceeding on empty values

## External Commands: jq, grep & Portability

- `jq` exits `0` even when a filter yields `null` or `empty` — check for `null`/empty explicitly when a value is required; use `// "default"` for absent fields, and `-e` when you want a non-zero exit on null/false
- `grep` exits `1` when it finds no match — under `set -e` or mid-pipeline this can abort the script or mask intent; guard with `|| true` when "no match" is a valid outcome
- Portability: `sed -i`, `grep -P`, `readlink -f`, `mktemp`, and `date` flags differ between BSD/macOS and GNU/Linux — avoid GNU-only flags or gate on the platform
- Prefer POSIX character classes (`[[:space:]]`, `[[:digit:]]`) over locale-fragile ranges like `[a-z]`
- Reach for `awk`/`sed` over fragile chains of `cut`/`head`/`tail`; parsing `ls` output is a known bug source — glob, or use `find -print0` with `read -d ''`

## Baseline Linting

- `shellcheck` is the baseline — a script that does not pass `shellcheck` clean (or does not justify each `# shellcheck disable=...`) is a finding
- Prefer the `shellcheck`-flagged fixes (SC2086 quoting, SC2155 masked return values, SC2164 `cd || exit`) over ad-hoc workarounds
