# Rust Review Criteria

## Ownership & Borrowing

- Unnecessary clones — `.clone()` used to appease the borrow checker instead of restructuring; each clone should be justified
- Borrow vs move — prefer borrowing (`&T`, `&mut T`) when ownership transfer isn't needed
- Lifetime elision — don't annotate lifetimes when the compiler can infer them; explicit lifetimes should be meaningful
- Self-referential structs — these are almost always wrong; use indices, `Pin`, or restructure
- Returning references — ensure the lifetime of the return is tied to an input; avoid `'static` unless truly needed

## Lifetime Annotations

- Named lifetimes should be descriptive when multiple are in play (`'input`, `'conn` not `'a`, `'b`)
- Avoid `'static` bounds on trait objects unless the use case genuinely requires it
- Lifetime bounds on generics — `T: 'a` means `T` outlives `'a`; verify this is the actual constraint needed
- `&'_ T` — prefer elided lifetimes in function signatures for readability

## Unsafe Blocks

- Every `unsafe` block must have a `// SAFETY:` comment explaining why the invariants hold
- Minimize the scope of `unsafe` — extract the smallest possible unsafe operation, wrap in a safe API
- No undefined behavior — verify alignment, aliasing rules, and validity invariants
- FFI boundaries — null pointer checks, proper `repr(C)`, ownership semantics documented
- `unsafe impl` for traits (`Send`, `Sync`) — must justify why the type actually satisfies the contract
- Audit all raw pointer dereferences — verify the pointer is non-null, aligned, and points to valid memory

## Error Handling (Result / Option)

- Use `Result<T, E>` for recoverable errors — not `panic!`
- Error types — prefer `thiserror` for library errors, `anyhow` for application errors
- `unwrap()` / `expect()` — only acceptable in tests, examples, or with a comment proving it can't fail
- `?` operator — prefer over explicit `match` on `Result`/`Option` for propagation
- Don't discard errors — no `let _ = fallible_fn();` without justification
- `Option` vs sentinel values — use `Option<T>` instead of magic values (`-1`, `""`, etc.)
- Error context — chain errors with `.context()` (anyhow) or custom `From` impls

## Panic vs Recoverable Errors

- `panic!` is for programmer errors (violated invariants), not for expected failure modes
- `todo!()`, `unimplemented!()` — acceptable only in prototype code, never in production paths
- Array/slice indexing — prefer `.get()` with proper handling over direct `[]` indexing in non-trivial code
- Integer overflow — use `checked_*`, `saturating_*`, or `wrapping_*` methods for arithmetic that could overflow
- `unwrap_or`, `unwrap_or_else`, `unwrap_or_default` — prefer over bare `unwrap()`

## Trait Design

- Keep traits focused — single responsibility; compose with supertraits or blanket impls
- Default method implementations — provide where the default is obviously correct
- Associated types vs generics — use associated types when there's one natural choice per implementor
- `Display` vs `Debug` — implement `Display` for user-facing output, `Debug` for developer diagnostics
- Orphan rule — can't implement external traits for external types; use newtype pattern
- `Deref` / `DerefMut` — only implement for smart pointer types, not for "inheritance"

## Concurrency

- `Send` + `Sync` — verify types crossing thread boundaries satisfy these bounds
- `Arc<Mutex<T>>` — prefer `RwLock` when reads dominate; avoid holding locks across `.await`
- Channel selection — `mpsc` for simple producer-consumer; `crossbeam` channels for complex patterns
- Deadlocks — consistent lock ordering; avoid nested locks
- `async` — don't block the runtime with CPU-bound work; use `spawn_blocking`
- Shared mutable state — prefer message passing over shared memory where practical

## Common Pitfalls

- Unused `must_use` returns — `Result`, `MutexGuard`, iterators are `#[must_use]`; don't ignore them
- Iterator vs loop — prefer iterator chains (`.map`, `.filter`, `.collect`) over manual `for` loops with mutation
- String types — `&str` for borrowed, `String` for owned; don't allocate when a borrow suffices
- `Copy` vs `Clone` — implement `Copy` only for small, stack-only types
- Feature flags — ensure no compilation errors with different feature combinations
- `derive` ordering — conventional order: `Debug, Clone, Copy, PartialEq, Eq, Hash, ...`
