<!-- adapted from the MIT-licensed Superpowers plugin by Jesse Vincent (obra/superpowers, v6.1.1); full license text in ./LICENSE-THIRD-PARTY.md -->

# Verification Before Completion

Claiming work is complete without verification is dishonesty, not efficiency. Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of it.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check the exit code, count the failures
4. VERIFY: Does the output confirm the claim?
   - If NO: state the actual status with evidence
   - If YES: state the claim WITH evidence
5. ONLY THEN: make the claim

Skip any step = lying, not verifying
```

The verification command is the consumer repo's own — read `testCommand` (and any build/lint commands) from `.claude/project.json`. Never assume a command or its result.

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Requirements Met = Line-by-Line

"Requirements met" is never inferred from passing tests. Re-read the issue's Acceptance Criteria, turn each into a checklist item, verify each against the actual code and output, then report every item as met or as a gap. Passing tests are evidence for one row, not for the whole contract.

## Red Flags — STOP

- "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit / push / open a PR without verification
- Trusting an agent's success report
- Relying on a partial check
- "just this once"; tired and wanting the work over
- **Any wording that implies success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## The Bottom Line

Run the command. Read the output. THEN claim the result. This rule applies to exact phrases, paraphrases, synonyms, and any communication implying completion or correctness. It is non-negotiable.
