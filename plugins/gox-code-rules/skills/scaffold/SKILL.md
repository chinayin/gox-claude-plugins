---
name: scaffold
description: >-
  Team standards for repository-level files — everything that is not source code: `Makefile`, `.editorconfig`, `.gitignore`, `.dockerignore`, `Dockerfile`, `.golangci.yml`, `.golangci-lint-version`, `.goreleaser.yaml`, `.goreleaser-version`, `.gitlab-ci.yml`, `.github/workflows/*.yml`, the README, and release tags. Use whenever you create or edit one of these files, start a new project or repo, add or change CI, package a release, build an image, or choose a tag or version number — in a Go, shell, or any other repo, even when the user only says "add CI", "set up the project" or "cut a release".
paths: "Makefile, .editorconfig, .gitignore, .dockerignore, Dockerfile, .golangci.yml, .golangci-lint-version, .goreleaser.yaml, .goreleaser-version, .gitlab-ci.yml, .github/workflows/*.yml"
---

# Repository Scaffold Standards

Rules for the files that make a repository buildable, checkable and releasable. Source code stays
with the language skills (`go`, `shell`, `bashly`, `frontend`). The sections below apply to every
repo; read the references **on demand** — only the ones the repo matches.

## When to read which (index)

Decide from what is in the repo, not from how the request is worded.

| The repo has | Read this |
|---|---|
| A `go.mod` — `Makefile`, `.golangci.yml`, version dotfiles, `.goreleaser.yaml`, `Dockerfile` | `references/go.md` |
| Shell scripts as the product, or a `bashly.yml` | `references/shell.md` |
| A GitHub remote — `.github/workflows/*.yml` | `references/github.md` |
| A GitLab remote — `.gitlab-ci.yml` | `references/gitlab.md` |

A repo runs one CI system, the one its remote hosts (`git remote get-url origin`). Never add
`.github/workflows/` to a GitLab repo or a `.gitlab-ci.yml` to a GitHub one. With no remote yet,
ask which host the repo will live on before writing any CI file.

## Versions

- A tool version is written **once**, in a root dotfile, and everything else reads it:
  `.golangci-lint-version`, `.goreleaser-version`, and `go.mod` for Go itself. No workflow,
  Makefile or Dockerfile repeats the number.
- Never write a version from memory — it is stale by the time you type it. When you create a
  version dotfile, look the value up:
  - CI runs on a prebuilt image that ships the tool (`references/gitlab.md`) → the version in that
    image.
  - Otherwise → the latest release, through the Go module proxy:
    `go list -m github.com/golangci/golangci-lint/v2@latest`.
- Do not bump an existing version file unless asked to.
- GitHub Actions are pinned to a major tag (`@v7`), the same major in every workflow of the repo.
  Look up the current major before writing one:
  `gh api repos/<owner>/<action>/releases/latest -q .tag_name`.

## .editorconfig

Identical in every repo:

```editorconfig
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.go]
indent_style = tab

[Makefile]
indent_style = tab

[*.{sh,bash,bats}]
indent_size = 2

[*.{yaml,yml,toml,json}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

## .gitignore

Every repo starts from this block; the language references add to it.

```gitignore
# Secrets and local overrides; only the examples are tracked
.env
.env.*
!.env.example

# Machine-local artifacts: exports, e2e output, virtualenvs
/local/

# OS and editors
.DS_Store
.idea/
.vscode/
*.swp
*.swo

# Agent tooling
.claude/worktrees/
.superpowers/
.worktrees/
.codegraph/
.kiro/
```

Files that exist only on one machine go under `/local/`. The pattern is anchored to the root so a
tracked directory deeper in the tree may still be called `local`.

## Makefile

Every repo's `Makefile` starts from this skeleton; the language references add their targets to
it and list them in `.PHONY`.

```makefile
.DEFAULT_GOAL := help
.PHONY: help

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-13s - %s\n", $$1, $$2}'
```

At least these targets exist:

| Target | Does |
|---|---|
| `help` | Default target; lists the targets from their `## ` comments |
| `test` | Runs the tests |
| `lint` | Runs the static checks |
| `check` | Everything to run before a commit — CI runs the same thing |

- Every target is listed in `.PHONY`.
- Every public target carries a `## ` comment; internal ones (`ensure-*`) omit it and stay out of
  `help`.
- Recipes are prefixed with `@`.
- A target that needs a tool either installs the pinned version itself or stops with an `Error:`
  line saying how to install it. It never falls back to whatever version is on PATH.

## Release tags

| Repo | Scheme | Examples |
|---|---|---|
| A deployed service — released by date, imported by nobody | CalVer `vYY.M.D`; a further release the same day appends `-N` | `v26.11.26`, `v26.11.26-1` |
| A tool or library that others install or import | SemVer `vX.Y.Z` | `v0.8.0` |

- No zero padding: `v27.1.5`, never `v27.01.05`. The shared CI tag rules do not match a segment
  with a leading zero.
- Never a fourth dotted segment (`v26.11.26.1`): it is not a semantic version and goreleaser
  refuses it. Never `+N`: `+` is not a valid character in an image tag.
- Under SemVer precedence `-N` sorts before the bare date. Order releases by date, never by a
  SemVer sort.

## README

`README.md` is the primary one. A Chinese edition is `README_CN.md` beside it, and each links to
the other in its first lines.

> These are in-session **soft guidance**; the final enforcement is the repo's CI / PR review.
