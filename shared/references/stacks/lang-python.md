# Python Review Criteria

## Type Hints

- All public function signatures should have type annotations (parameters and return types)
- Use native union syntax (`X | None`) — requires Python 3.10+; do not use `from __future__ import annotations`
- Prefer `collections.abc` types (`Sequence`, `Mapping`, `Iterable`) over concrete types in parameters
- Use `TypedDict` for structured dictionaries, not `dict[str, Any]`
- Built-in generics — `list[int]`, `dict[str, T]`, `tuple[int, ...]` (Python 3.9+)
- `Any` should be rare and justified — it disables type checking for everything it touches
- Protocol classes for structural subtyping — prefer over ABCs when duck typing is the intent
- `TypeVar` constraints — use `bound=` for upper bounds, not unconstrained type vars
- Use `ty` for type checking — flag configurations that aren't compatible with it

## Data Validation & Serialization

- Use Pydantic models for external data boundaries (API requests/responses, config files, message payloads)
- Pydantic `BaseModel` over raw dicts for structured data — provides validation, serialization, and documentation
- Use `Field(...)` for constraints, defaults, and descriptions
- Prefer Pydantic's validators (`field_validator`, `model_validator`) over manual validation logic
- Settings management — use `pydantic-settings` for env-var-backed configuration

## Async / Await

- Don't mix sync and async — blocking calls (`time.sleep`, synchronous I/O) in async code block the event loop
- Use `asyncio.to_thread()` or `run_in_executor()` for unavoidable blocking operations
- `async for` / `async with` — use for async iterators and context managers
- Task cancellation — handle `asyncio.CancelledError`; clean up resources in `finally`
- `asyncio.gather` — use `return_exceptions=True` when partial failures are acceptable
- Don't create event loops inside async functions — use the running loop
- HTTP clients — use `httpx` (supports both sync and async) over `requests` or `aiohttp`
- Connection pools — use async-compatible drivers (`asyncpg`, `httpx.AsyncClient`)

## Logging

- Use `loguru` over stdlib `logging` — simpler configuration, structured output, better defaults
- Use structured logging with bound context (`logger.bind(request_id=...)`)
- Log levels should be meaningful — `debug` for development, `info` for operational events, `error` for failures
- Don't use `print()` for application logging

## Dependency & Environment Management

- `uv` is the required tool for dependency management, virtual environments, and Python version management
- `pyproject.toml` for all project metadata (PEP 621) — `setup.py`, `setup.cfg`, `requirements.txt` are legacy
- `uv.lock` must be committed — ensures reproducible builds across environments
- Dependency groups (`[dependency-groups]`) to separate dev/test/lint from production
- Check for known vulnerabilities in dependencies
- Version constraints — use bounded ranges, not uncapped (`>=`)
- Never install packages globally — `uv` manages isolated environments automatically

## Linting & Formatting

- Use `ruff` for both linting and formatting — replaces flake8, isort, black, pyflakes, and others
- `ruff` configuration belongs in `pyproject.toml` under `[tool.ruff]`
- Import sorting handled by `ruff` — standard library, third-party, local, separated by blank lines

## Exception Handling

- Never use bare `except:` — catches `SystemExit`, `KeyboardInterrupt` etc.
- Catch specific exceptions — `except ValueError` not `except Exception`
- Don't silence exceptions without logging — no empty `except` blocks
- Use `raise ... from err` to chain exceptions and preserve tracebacks
- Custom exceptions should inherit from domain-specific base, not directly from `Exception`
- `finally` for cleanup — especially file handles, connections, temp files
- Context managers (`with`) — use for any resource with setup/teardown; implement `__enter__`/`__exit__` or use `contextlib`

## Import Structure

- Standard library → third-party → local — separated by blank lines (enforced by `ruff`)
- Absolute imports preferred over relative — except within packages where relative is clearer
- No wildcard imports (`from module import *`) — pollutes namespace, breaks tooling
- Avoid circular imports — restructure with dependency inversion or lazy imports
- Import at module level, not inside functions — unless lazy loading is intentional and documented

## Common Pitfalls

- Mutable default arguments — `def f(items=[])` shares the list across calls; use `None` sentinel
- Late binding closures — `lambda` in loops captures the variable, not the value; use default arg `lambda x=x:`
- `is` vs `==` — `is` for identity (None, sentinel), `==` for equality
- String concatenation in loops — use `"".join(parts)` or `io.StringIO`
- Global state — module-level mutable state makes testing and concurrency painful
- `__init__.py` bloat — keep package `__init__` minimal; don't re-export everything
- `datetime` — always use timezone-aware datetimes (`datetime.now(tz=UTC)`); naive datetimes cause bugs
- f-strings — prefer over `.format()` and `%` for readability
- Dictionary access — use `.get(key, default)` or check `key in dict` before `dict[key]` for optional keys
- Comprehensions — prefer over `map`/`filter` with lambdas; but avoid deeply nested comprehensions
