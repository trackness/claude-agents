# Docker Review Criteria

## Build Optimization

- Multi-stage builds — separate build dependencies from runtime image
- Layer caching — order instructions from least to most frequently changing; `COPY` dependency manifests before source code
- `.dockerignore` — exclude `node_modules`, `.git`, build artifacts, test files, docs
- Minimize layer count — combine related `RUN` commands with `&&`
- Use `--mount=type=cache` for package manager caches (npm, pip, apt)
- Pin base image versions — `node:20.11-slim` not `node:latest`

## Image Size

- Use slim/alpine base images — `python:3.12-slim` not `python:3.12`
- Remove package manager caches in the same layer — `apt-get clean && rm -rf /var/lib/apt/lists/*`
- Don't install unnecessary packages — no `vim`, `curl` in production images unless required
- Copy only what's needed — specific files/dirs, not entire context
- Check final image size — flag images over 500MB for review

## Security

- Run as non-root — `USER nonroot` or `USER 1000`; never run application processes as root
- Don't store secrets in image layers — use build args, runtime env vars, or secret mounts
- Scan base images for CVEs — use `docker scout` or equivalent
- Minimal base images reduce attack surface — `distroless` for production where possible
- No `--privileged` flag in runtime unless absolutely necessary and documented
- Read-only root filesystem where possible (`--read-only`)

## Health Checks

- `HEALTHCHECK` instruction present — define meaningful health endpoints
- Health check interval and timeout appropriate for the service
- Health check command should be lightweight — don't hit expensive endpoints
- Health check should verify the service is actually functional, not just that the process is running

## Runtime

- `EXPOSE` documents the correct ports — matches actual application listening ports
- `ENTRYPOINT` vs `CMD` — use `ENTRYPOINT` for the main process, `CMD` for default arguments
- Signal handling — process must handle `SIGTERM` for graceful shutdown (PID 1 problem; use `tini` or `dumb-init` if needed)
- Logging to stdout/stderr — don't write logs to files inside the container
- Environment variable configuration — don't hardcode config that varies between environments

## Compose / Orchestration

- Service dependencies — `depends_on` with health check conditions, not just startup order
- Volume mounts — named volumes for persistent data, bind mounts only for development
- Network isolation — services that don't need to communicate shouldn't share a network
- Resource limits — set memory and CPU limits to prevent runaway containers
- Restart policies — appropriate for the service type (`unless-stopped` for daemons, `no` for one-shot tasks)
