---
name: go
description: Team Go microservice architecture and coding standards. Use this whenever designing or writing Go code in this repo — HTTP services and handlers (gin), CLI commands (cobra), configuration (gox/config), database migrations (goose), or project scaffolding (Makefile/CI). Consult it any time you touch Go code or plan a Go module — including small changes like reading a single environment variable, secret, or config value — even if the user never says "standards".
paths: "**/*.go, go.mod, go.work, go.sum"
---

# Team Go Standards

Follow team conventions when writing or designing Go code in this repo. **Reply and write code comments in Chinese.** Read the detailed standards in `references/` **on demand** per the index below — do not read them all at once, only the file relevant to the current task.

## When to read which (index)

| What you're doing | Read this |
|---|---|
| Writing **any** Go code (baseline: versions, logging, errors, concurrency, naming…) | `references/rules.md` ← read first by default |
| Shaping code beyond the baseline: over a complexity limit, laying out a new package, designing options/structs/interfaces, generics | `references/code-style.md` |
| Starting or restructuring a project (CLI vs DDD layout), Protobuf schemas, gRPC clients, docs file naming | `references/service-layout.md` |
| Writing/designing **HTTP** services: routing, handlers, middleware, request/response, logging, request-id/trace, handler tests (gin) | `references/http.md` |
| Designing/writing CLI commands under `cmd/**` (cobra + gox/cli) | `references/cli.md` |
| Configuration loading (`config/**`, `main.go`/`config.go`, `bootstrap/`, gox/config) | `references/config.md` |
| Database migrations / schema (`migrations/`, `dbmigrate/`, `store.go`, `*migrate*`, `*migration*`, `*schema*`, goose) | `references/db-migrations.md` |
| Time **persisted or crossing a system boundary**: time/date columns (`DATETIME` vs epoch), GORM `autoCreateTime`/`autoUpdateTime`, DSN `loc`/`time_zone`, parsing external timestamps, time fields in API contracts, daily cutoff / timezone logic. In-process time (durations, timers, `time.Since`, sleeps) does NOT need this | `references/time-and-timezone.md` |
| Project scaffolding (`Makefile`, `.gitignore`, `.editorconfig`, `.golangci-lint-version`, `.github/workflows/*.yml`) | `references/scaffold.md` |

## Core rules (highest priority; details in rules.md)

- Go 1.26+; JSON/protobuf fields use snake_case.
- Logging: initialize gox/log at the entry point, use log/slog in business code; **never log with fmt**.
- Config: use gox/config exclusively; **never** use viper directly or bare `os.Getenv` in business code.
- HTTP services use gin: `gin.New()` (never `gin.Default()`); request-scoped identity lives in
  `c.Request.Context()`, **never** `c.Set`/`c.MustGet`.
- Logging: `slog.SetDefault` is called **exactly once, at the entry point** (gox/log embeds
  `*slog.Logger`); the HTTP layer never calls it and takes no logger parameter. Redirect
  `gin.DefaultWriter`/`DefaultErrorWriter` so gin's own output cannot bypass slog.
- `request_id` (reused from inbound `X-Request-Id`, else generated) and OpenTelemetry
  `trace_id` both travel in ctx and are attached to every log record by a `slog.Handler`.
- All external calls must set a timeout (internal 10s, external 30s).
- No package-level mutable global state; wrap errors with a package prefix.

> These are in-session **soft guidance**; the final enforcement is the repo's `golangci-lint` / CI / PR review.
