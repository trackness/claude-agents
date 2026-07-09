# TypeScript / React / Node.js Review Criteria

## React / Frontend

- Component design and composition — prefer small, focused components over monoliths
- Hook dependencies and cleanup — verify `useEffect` deps arrays are complete and effects clean up subscriptions/listeners
- State management appropriateness — local state vs context vs external store; avoid prop drilling
- Accessibility (a11y) — semantic HTML, ARIA labels, keyboard navigation, focus management
- Prop types / TypeScript types — no `any` props, interfaces for component props
- Key props in lists — stable, unique keys (not array index for dynamic lists)
- `useEffect` dependency arrays — missing deps cause stale closures, extra deps cause unnecessary re-renders
- Unnecessary re-renders — missing `useMemo`/`useCallback` on expensive computations or callback props
- Bundle size impact — large new dependencies, missing tree-shaking, dynamic imports for heavy routes
- Controlled vs uncontrolled components — consistent form handling patterns
- Error boundaries — present around async/fallible UI subtrees
- CSS/styling — unused styles, specificity conflicts, responsive design gaps

## Node.js / Backend

- Async/await vs callbacks — prefer async/await; no mixing patterns in the same flow
- Middleware order — **critical**: auth/validation middleware must run before route handlers
- Request validation — validate and sanitize all user input at the boundary
- Response status codes — correct HTTP semantics (201 for creation, 404 vs 400, etc.)
- API versioning — breaking changes require version bumps
- Rate limiting — public endpoints must have rate limits
- Database connection handling — connection pooling, proper release on error
- Stream handling for large data — don't buffer entire payloads into memory
- Error responses — consistent error shape, no stack traces in production

## TypeScript-Specific

- Implicit `any` — no untyped variables or parameters; enable `noImplicitAny`
- Missing return types — public/exported functions should have explicit return types
- Unsafe type assertions — avoid `as` and `!` (non-null assertion); prefer type guards
- `unknown` vs `any` — use `unknown` for truly unknown data, narrow with guards
- Strict null checks — handle `null`/`undefined` at boundaries, not with `!`
- Interface vs type — use interfaces for object shapes, types for unions/intersections
- Enums — prefer `as const` objects or union types over numeric enums
- Generic constraints — constrain type parameters (`<T extends Base>`) rather than using `any`
