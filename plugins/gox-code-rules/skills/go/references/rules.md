# Go Microservice Development Rules

You are a Go expert. Write code that follows these team conventions.
Reply and write code comments in Chinese.

This file is the baseline for any Go change. Load the companions only when the task
needs them: `references/code-style.md` (complexity patterns, package file layout
details, options/struct/interface/generics design, pitfall examples) and
`references/service-layout.md` (CLI vs DDD project structure, Protobuf, gRPC client,
docs file naming).

## Top Priority

- Go version: Go 1.26+ for all projects (services, apps, and public libraries).
- Logging: Initialize at entry point with gox/log, use log/slog in business code (see Logging section)
- JSON struct tags: snake_case (`json:"user_id"`)
- Protobuf fields: snake_case
- All external calls must have timeout (internal 10s, external 30s)

## Naming

- Package: lowercase, short, meaningful, no underscores
- Local vars: short names (ctx, err, cfg, buf, req, resp)
- Package vars: full names (DefaultTimeout, MaxRetryCount)
- Abbreviations stay uppercase: ID, URL, HTTP, JSON, XML
- No type prefixes: `userID` not `intUserID`

## Error Handling (MUST)

- Check and handle every error return
- Package errors: `Err` prefix, defined in `errors.go`
- Format: `"package: description"` (lowercase, no trailing punctuation)
- Wrap with `fmt.Errorf("pkg: action %q: %w", arg, err)`
- Compare with `errors.Is` / `errors.As`

## Logging (MUST)

- Entry point initialization: Use `github.com/chinayin/gox/log` to create logger and set global slog handler
  - Microservices: in `internal/bootstrap/` or `internal/adapter/bootstrap/`
  - CLI tools: in `cmd/<app>/main.go` assembly code
- Business code: Use standard library `log/slog` directly, since global handler is set by gox/log
- Contextual logging: `slog.With("key", value)` to create child logger
- Forbidden: directly importing zap/logrus or other third-party logging libraries

## Code Quality (MUST)

- Cyclomatic complexity <= 15
- Cognitive complexity <= 20
- Nesting depth <= 4
- After completing a feature or fixing multiple files, run `make lint-fix` before presenting results (uses the project-pinned golangci-lint, never the global one). If the project has no `lint-fix` target, fall back to the pinned version without any global install: `go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(cat .golangci-lint-version) run --fix ./...`. Fix auto-fixable issues silently; for warnings requiring judgment, analyze and fix properly (no blind nolint).
- Over the limit? Reshape, do not suppress: early return instead of mixed branches, extract print/format helpers out of loops, merge identical switch cases (`references/code-style.md`).

## Package File Organization (MUST)

Standard file layout:

```
doc.go      - package documentation
const.go    - constants shared across files (referenced by multiple files in same package)
errors.go   - package-level errors (Err prefix, with comments)
types.go    - shared types first, then constants
<impl>.go   - implementation, file-local constants declared at top of file
```

Constant placement and a full example: `references/code-style.md`.

## Constructor Conventions (MUST)

- Naming: `New<Type>` or `New<Type>From<Source>`
- Return pointer: `func NewClient() *Client`
- Return error if may fail: `func New() (*Client, error)`
- Use Functional Options when 3+ optional parameters (`references/code-style.md`)

## Type Design (SHOULD)

Field order, receiver naming, small consumer-side interfaces, where generics pay off:
`references/code-style.md`.

## Concurrency (MUST)

- Context as first parameter, always
- Explicit goroutine lifecycle with Context
- Sender closes channel
- Use WaitGroup or errgroup
- Limit goroutine count

## Standard Library

- Use `slices` package: Sort, Index, Contains
- Use `maps` package: Clone, Copy, Equal
- Use `cmp` package: Compare, Or

## Testing (MUST)

- Name: `Test<Component>_<Method>_<Scenario>`
- Table-driven with `[]struct` + `t.Run`
- Each test independent, no shared state
- Use testify (assert + require)
- AAA pattern: Arrange, Act, Assert
- Use gomock for mocking — the maintained `go.uber.org/mock` (the original golang/mock is archived); `defer ctrl.Finish()` to verify expectations

### Coverage Requirements

- Utility functions: 100%
- Domain models: > 90%
- Service layer: > 80%

## API Design (MUST for HTTP services)

- RESTful style, resources use plural nouns: /users, /orders
- Version prefix: /v1, /v2
- JSON field names: snake_case
- Unified response / error body: single source in `references/http.md` → "Response"
- Timestamps: ISO 8601 UTC

For handler-level conventions (gin framework choice, engine setup, routing, middleware set,
ctx vs `c.Set`, slog wiring, request-id and trace propagation, parameter whitelisting, handler
tests), see `references/http.md`.

## Microservice Governance (MUST)

- Naming: business microservice project name ends with `-svc` (e.g. `order-svc`, `user-svc`)
- Service ports: HTTP `:8000` (PORT), gRPC `:9000` (GRPC_PORT)
- Health checks: `/health/live` (liveness), `/health/ready` (readiness)
- Tracing: propagate Trace ID across services
- Rate limiting and circuit breaker for all inbound endpoints

## Project Structure

CLI tools: `cmd/<app>/main.go` (assembly only) + `internal/<app>/`. Business microservices:
DDD layout under `internal/`, organized by aggregate root, adapters under `internal/adapter/`.
Full trees, Protobuf and gRPC client rules: `references/service-layout.md`.

## Common Pitfalls

- Design types so the zero value is usable (a nil slice appends; no mandatory init call).
- No package-level mutable state; inject dependencies through constructors.
- Never store a Context in a struct; pass it as the first parameter.

Examples: `references/code-style.md`.

## gox Library

Use github.com/chinayin/gox for:
log, config, discovery, trace, metrics, middleware, transport, utils

## Scaffold Files (MUST)

Every Go project root must have: `.editorconfig`, `.gitignore`, `Makefile`.
Refer to `references/scaffold.md` for standard templates.

## Documentation (MUST)

- All docs in `docs/` directory
- Filename: UPPER_SNAKE_CASE.md
- Must contain: title, overview, main content

Exception: tool/skill-managed namespaces under `docs/` are excluded from this rule — do not rename them or their files. E.g. `docs/superpowers/` is a date-ordered namespace whose plans use `YYYY-MM-DD-*.md`; leave such subdirectories as-is.

Conventional file names: `references/service-layout.md`.
