# Project Layout, Protobuf, gRPC Client

Companion to `references/rules.md`. Read when starting or restructuring a project,
defining Protobuf schemas, writing a gRPC client, or naming project documentation.
Wire contracts for HTTP (RESTful, versioning, unified body, health probes) stay in
`rules.md` → "API Design" / "Microservice Governance"; handler-level rules are in
`references/http.md`.

## Project Structure

CLI tools use standard layout:

```
cmd/<app>/main.go     - entry point, assembly only
internal/<app>/       - core business logic
  const.go            - shared constants across files
  errors.go           - package errors
  types.go            - shared types
config/               - config files (config.local.yaml gitignored)
docs/                 - project documentation (UPPER_SNAKE_CASE.md)
bin/                  - build output (gitignored)
```

Business microservices use DDD layout (organize by aggregate root, not tech layer):

```
internal/
  <aggregate>/        - domain aggregate
    domain.go         - entity, value object, repository interface
    service.go        - domain service (business logic)
    repository.go     - repository interface (defined in domain layer)
    events.go         - domain events
  adapter/            - ports and adapters
    grpc/             - gRPC handlers
    http/             - HTTP handlers
    repository/       - repository implementations (GORM/Redis)
  bootstrap/          - app init and DI
```

For CLI-specific conventions (framework, subcommands, flags, version injection, local config repository), see `references/cli.md`.
For the mandatory root files (`.editorconfig`, `.gitignore`, `Makefile`), see `references/scaffold.md`.

## Protobuf (MUST)

- Fields: snake_case (never camelCase)
- Enum values: UPPER_SNAKE_CASE
- Zero value: `STATUS_UNSPECIFIED = 0`
- Never delete/rename fields or change field numbers
- Use `reserved` to preserve deleted field numbers

## gRPC Client (MUST)

- Set timeout via `context.WithTimeout`
- Check status codes with `status.Code(err)`
- Convert gRPC status to business error codes
- Retry only idempotent ops, max 3 times, exponential backoff
- POST operations use idempotency key
- Use circuit breaker to prevent cascade failures (SHOULD)
- Propagate OpenTelemetry trace context (SHOULD)

## Documentation file naming

Rules (location, case, required sections, exempt namespaces) are in `rules.md` → "Documentation".
Conventional names:

- Architecture: ARCHITECTURE.md
- API: API_REFERENCE.md, API_GUIDE.md
- Testing: TESTING_*.md, E2E_TEST_*.md
- Migration: *_MIGRATION_GUIDE.md, *_MIGRATION_STATUS.md
- Integration: *_INTEGRATION_GUIDE.md, *_INTEGRATION_SUMMARY.md
- Status: *_STATUS.md, *_SUMMARY.md
