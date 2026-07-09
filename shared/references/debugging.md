<!-- adapted from the MIT-licensed Superpowers plugin by Jesse Vincent (obra/superpowers, v6.1.1) -->

# Systematic Debugging

Random fixes waste time and create new bugs. Find the root cause before attempting any fix — a symptom fix is a failure.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose a fix. This holds hardest under pressure — "just one quick fix," an emergency, or a check that must clear NOW. Systematic debugging is faster than guess-and-check thrashing.

## Start Here: What Did You Just Change?

In /ship the failure almost always surfaces right after a commit — a test went red, CI broke, a check failed. Before anything else:

- `git diff` the change and `git log` the recent commits. The regression is almost certainly in what you just touched.
- Read the failure output completely — stack trace, line numbers, file paths, error codes. It often names the exact cause.
- Reproduce it reliably. Not reproducible → gather more data, don't guess.

## The Four Phases

Complete each phase before the next.

**Phase 1 — Root cause.** Read the error, reproduce consistently, check recent changes. In a multi-component path (CI → build → sign; API → service → DB), add diagnostic logging at each boundary — log what enters and what exits each component — run once to see WHERE it breaks, then investigate that component. Understand WHAT breaks and WHY before proposing anything.

**Phase 2 — Pattern.** Find similar working code in the same repo. If you're following a reference implementation, read it completely — every line, no skimming. List every difference between the working and broken versions, however small; never assume "that can't matter."

**Phase 3 — Hypothesis.** State one hypothesis: "I think X is the root cause because Y." Test it with the SMALLEST possible change — one variable at a time. Worked → Phase 4. Didn't → form a NEW hypothesis; do not stack more fixes on top. Don't understand something? Say so; don't pretend to know.

**Phase 4 — Implementation.** Write a failing test that reproduces the bug (follow `tdd.md`). Implement ONE fix at the root cause — no "while I'm here" changes, no bundled refactoring. Verify: the test passes, no other test broke, the issue is actually resolved.

## The Circuit Breaker

```
Fix didn't work?
  Count your attempts.
  < 3  → return to Phase 1, re-analyze with the new information
  ≥ 3  → STOP. Do not attempt fix #4. Question the architecture.
```

Three or more failed fixes is not a failed hypothesis — it's a wrong architecture. The signs: each fix reveals new coupling somewhere else, each fix demands "massive refactoring," each fix spawns a new symptom. Raise it with the user before touching the code again.

## Red Flags — STOP, Return to Phase 1

"Quick fix for now, investigate later" · "just try changing X" · "add several changes, run tests" · "skip the test, I'll verify manually" · "it's probably X" · "I don't fully understand it but this might work" · listing fixes before tracing the data flow · "one more attempt" after two-plus failures.

## Companion Techniques

**Trace to the original trigger.** When the error surfaces deep in the call stack, don't fix where it appears. Trace backward — what passed the bad value? what called that? — until you reach the origin, and fix there. When manual tracing dead-ends, log the directory, `cwd`, environment, and `new Error().stack` right before the dangerous operation, then read the chain. Never fix just the symptom point.

**Poll for the condition, don't sleep.** Flaky waits guess at timing with an arbitrary `sleep`/`setTimeout` and race under load. Wait for the actual condition instead — poll the state, event, or file every ~10ms with a timeout that throws a clear error. An arbitrary delay is legitimate only for genuine timing behavior (debounce, throttle intervals), and only with a comment stating why.

**Validate the invariant at every layer.** After finding the root cause, don't rely on a single check — one guard is bypassed by other code paths, refactors, or mocks. Validate at each layer the data passes through: the entry point rejects bad input, business logic confirms the data makes sense for the operation, an environment guard blocks the dangerous context, and debug logging captures forensics when the others miss. Make the bug structurally impossible.
