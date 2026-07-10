<!-- adapted from the MIT-licensed Superpowers plugin by Jesse Vincent (obra/superpowers, v6.1.1); full license text in ./LICENSE-THIRD-PARTY.md -->

# Test-Driven Development

Write the test first. Watch it fail. Write minimal code to pass. If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of these rules is violating the spirit of them.**

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before the test? Delete it. Start over.

**No exceptions:**
- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

Implement fresh from the tests. Period. (Throwaway prototypes, generated code, and config files are the only exceptions, and only with the user's explicit sign-off.)

## The Cycle: Red → Green → Refactor

**RED — write one failing test** for a single behavior. Clear name, real code, no mocks unless unavoidable.

**Verify RED — MANDATORY, never skip.** Run the consumer repo's test command (`.claude/project.json` → `testCommand`) against the new test. Confirm it fails (not errors), the message is the one you expect, and it fails because the feature is missing, not because of a typo. Passes already? You're testing existing behavior — fix the test. Errors instead of failing? Fix the error, re-run until it fails correctly.

**GREEN — write the simplest code that passes.** No extra features, no refactoring of unrelated code, no gold-plating beyond the test.

**Verify GREEN — MANDATORY.** Run the test command again: the test passes, every other test still passes, output is pristine (no errors, no warnings). Still fails? Fix the code, not the test.

**REFACTOR — only after green.** Remove duplication, improve names, extract helpers. Keep the tests green; add no behavior. Then write the next failing test.

## Good Tests

- **Minimal** — one behavior. An "and" in the name means split it.
- **Clear** — the name describes the behavior, not `test1`.
- **Real** — exercises real code; mocks only when unavoidable.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Tests after achieve same goals" | Tests-after = "what does this do?" Tests-first = "what should this do?" |
| "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. Keeping unverified code is technical debt. |
| "Keep as reference, write tests first" | You'll adapt it. That's testing after. Delete means delete. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "Test hard = design unclear" | Listen to test. Hard to test = hard to use. |
| "TDD will slow me down" | TDD faster than debugging. Pragmatic = test-first. |
| "Manual test faster" | Manual doesn't prove edge cases. You'll re-test every change. |
| "Existing code has no tests" | You're improving it. Add tests for existing code. |

## Red Flags — STOP and Start Over

Code before test · test after implementation · test passes immediately · can't explain why the test failed · tests added "later" · "just this once" · "already manually tested it" · "keep as reference" or "adapt existing code" · "already spent X hours, deleting is wasteful" · "TDD is dogmatic, I'm being pragmatic" · "this is different because…"

**All of these mean: delete the code, start over with TDD.**

## Testing Anti-Patterns

```
1. NEVER test mock behavior
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies
```

**1. Testing mock behavior.** Asserting that a mock element exists verifies the mock, not the code under test.
```
BEFORE asserting on any mock element:
  Ask: "Am I testing real behavior or just mock existence?"
  IF testing mock existence:
    STOP - delete the assertion or unmock the component
  Test real behavior instead
```

**2. Test-only methods in production.** A method used only by tests pollutes the production class and is dangerous if ever called for real.
```
BEFORE adding any method to a production class:
  Ask: "Is this only used by tests?"
  IF yes:
    STOP - put it in test utilities instead
  Ask: "Does this class own this resource's lifecycle?"
  IF no:
    STOP - wrong class for this method
```

**3. Mocking without understanding.** Over-mocking "to be safe" strips side effects the test depends on, so it passes or fails for the wrong reason.
```
BEFORE mocking any method:
  STOP - don't mock yet
  1. What side effects does the real method have?
  2. Does this test depend on any of those side effects?
  3. Do I fully understand what this test needs?
  IF it depends on side effects:
    Mock at the lower level (the actual slow/external operation),
    NOT the high-level method the test depends on
  IF unsure what the test depends on:
    Run it against the real implementation FIRST, observe what must happen,
    THEN add minimal mocking at the right level
```

**4. Incomplete mocks.** Partial mocks hide structural assumptions and fail silently when code reads a field you omitted. Mock the COMPLETE structure as it exists in reality.
```
BEFORE creating mock responses:
  Check: "What fields does the real response contain?"
  1. Examine the actual response from docs/examples
  2. Include ALL fields the system might consume downstream
  3. Verify the mock matches the real schema completely
  If uncertain: include all documented fields
```

**5. Tests as an afterthought.** "Implementation complete, no tests, ready for testing" is not complete — testing is part of implementation, and the cycle above already prevents this.

Mocks are tools to isolate, not things to test. If TDD reveals you're testing mock behavior, test real behavior instead — or question why you're mocking at all.

## Final Rule

```
Production code → a test exists and failed first
Otherwise → not TDD
```
