---
name: go
description: Team Go microservice architecture and coding standards. Use this whenever designing or writing Go code in this repo — CLI commands (cobra), configuration (gox/config), database migrations (goose), or project scaffolding (Makefile/CI). Consult it any time you touch Go code or plan a Go module, even if the user never says "standards".
paths: "**/*.go, go.mod, go.work, go.sum"
---

# Team Go Standards

Follow team conventions when writing or designing Go code in this repo. **Reply and write code comments in Chinese.** Read the detailed standards in `references/` **on demand** per the index below — do not read them all at once, only the file relevant to the current task.

## When to read which (index)

| What you're doing | Read this |
|---|---|
| Writing **any** Go code (baseline: versions, logging, errors, concurrency, naming…) | `references/rules.md` ← read first by default |
| Designing/writing CLI commands under `cmd/**` (cobra + gox/cli) | `references/cli.md` |
| Configuration loading (`config/**`, `main.go`/`config.go`, `bootstrap/`, gox/config) | `references/config.md` |
| Database migrations / schema (`migrations/`, `*migrate*`, `store.go`, goose) | `references/db-migrations.md` |
| Project scaffolding (`Makefile`, `.golangci`, `.github/workflows/*`, `.editorconfig`) | `references/scaffold.md` |

## Core rules (highest priority; details in rules.md)

- Go 1.26+; JSON/protobuf fields use snake_case.
- Logging: initialize gox/log at the entry point, use log/slog in business code; **never log with fmt**.
- Config: use gox/config exclusively; **never** use viper directly or bare `os.Getenv` in business code.
- All external calls must set a timeout (internal 10s, external 30s).
- No package-level mutable global state; wrap errors with a package prefix.

> These are in-session **soft guidance**; the final enforcement is the repo's `golangci-lint` / CI / PR review.
