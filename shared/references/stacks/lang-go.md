# Go Review Criteria

## Error Handling

- Every error return must be checked — no `_` for error values unless explicitly justified
- Wrap errors with context using `fmt.Errorf("doing X: %w", err)` — bare `return err` loses call-site info
- Sentinel errors (`var ErrNotFound = errors.New(...)`) for errors callers need to match on; otherwise wrap
- Use `errors.Is` / `errors.As` for error matching — never compare error strings
- Don't log and return the same error — choose one to avoid duplicate noise
- Custom error types should implement `Error() string` and optionally `Unwrap() error`

## Goroutine & Concurrency

- Goroutine leaks — every goroutine must have a clear exit path (context cancellation, done channel, or bounded work)
- Channel usage — unbuffered channels block; ensure sender and receiver lifecycles match
- `sync.WaitGroup` — `Add` before launching goroutine, `Done` in defer
- Mutex scope — hold locks for the minimum necessary duration; never hold across I/O
- Race conditions — shared mutable state must be protected; run `go test -race`
- `select` with `context.Done()` — long-running goroutines must respect cancellation
- Never start goroutines in `init()` — lifecycle is uncontrollable

## Context Usage

- First parameter should be `ctx context.Context` — not embedded in structs
- Propagate context through the call chain — don't create new backgrounds mid-chain
- Use `context.WithTimeout` / `context.WithCancel` for bounding operations
- Never store contexts in structs — pass as function parameters
- Check `ctx.Err()` before expensive operations in loops

## Defer Patterns

- `defer` runs LIFO — order matters for cleanup sequences
- Defer immediately after acquiring a resource (`f, err := os.Open(...); if err != nil { ... }; defer f.Close()`)
- Beware defer in loops — resources won't be released until function exits; extract to helper function
- Defer with error checking — use named returns: `defer func() { if cerr := f.Close(); err == nil { err = cerr } }()`

## Interface Design

- Keep interfaces small — 1-2 methods; compose larger behaviors from small interfaces
- Define interfaces at the consumer, not the implementer
- Accept interfaces, return concrete types
- Don't export interfaces that have only one implementation — premature abstraction
- Use `io.Reader`, `io.Writer`, `fmt.Stringer` etc. from stdlib before inventing new ones

## Nil & Zero Values

- Check nil before dereferencing pointers — especially from map lookups and type assertions
- Zero values should be useful — design structs so the zero value is valid (e.g., `sync.Mutex`)
- Nil slices are valid (length 0, `append` works) — don't check for nil before ranging
- Nil maps panic on write — always `make(map[K]V)` or use composite literal before writing
- Type assertions — prefer comma-ok form (`v, ok := x.(T)`) to avoid panics

## Packages & Imports

- No circular imports — restructure with interfaces or move shared types to a leaf package
- Internal packages — use `internal/` to prevent external consumers from depending on implementation details
- Avoid package-level state — global `var` makes testing and concurrency harder
- `_test` package suffix — use for black-box testing of exported API

## Common Pitfalls

- String concatenation in loops — use `strings.Builder`
- `range` loop variable capture — in Go <1.22, loop vars are reused; capture before goroutine launch
- Struct copying with mutexes — never copy a struct containing a `sync.Mutex`
- `time.After` in loops — leaks timers; use `time.NewTimer` with `Reset`/`Stop`
- Slice append gotchas — `append` may or may not allocate; when sharing backing arrays, copy first
