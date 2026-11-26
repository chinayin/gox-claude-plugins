# Go Repository Files

Root files of a Go repo. Every Go repo has `.editorconfig`, `.gitignore`, `Makefile`,
`.golangci.yml` and `.golangci-lint-version`. One that ships a binary or an image also has
`.goreleaser.yaml`, `.goreleaser-version`, `Dockerfile` and `.dockerignore`. CI files:
`references/github.md` or `references/gitlab.md`.

## .gitignore

Append to the common block in `SKILL.md`:

```gitignore
# Build output and the pinned tools downloaded into bin/
bin/
dist/

# Local config overrides
config/*.local.yaml

# Written into the work tree by CI jobs; goreleaser refuses a dirty tree
.cache/
.go/
.go-build.json
```

## Go version

`go.mod` states the minimum, by minor only — the rule and its reason are in the `go` skill
(baseline rules, "Top Priority"). The patch release is whatever the build environment provides: the
CI image, `actions/setup-go` reading `go.mod`, the local install. A Dockerfile that compiles uses
`golang:<minor>`.

## .golangci-lint-version and .goreleaser-version

One line each, with the `v` prefix:

```
v2.15.0
```

The value is looked up, never typed from memory (`SKILL.md` → "Versions"). `make` reads these
files and installs exactly that release into `./bin`; CI reads them too, or ships the same release
in its image. Upgrading a tool is an edit to its file.

Two constraints when choosing a value:

- golangci-lint refuses to run when its binary was built with a Go older than the `go` line in
  `go.mod`. Pick a release built with Go at or above that line.
- goreleaser needs a Go as new as its own `go.mod` to build from source, and that is usually
  newer than the project's. Install the prebuilt binary; do not `go install` or `go run` it.

Tools are installed into the project's `./bin`, not globally and not with `go tool`: a global
install cannot be pinned per project, and golangci-lint's own documentation recommends its
binaries over `go install` and the `tool` directive.

## .golangci.yml

```yaml
version: "2"

linters:
  default: standard
  enable:
    - gocyclo
    - gocognit
    - revive
  settings:
    # Each limit reports a function above the number; they are the limits in the `go` skill's
    # baseline rules ("Code Quality")
    gocyclo:
      min-complexity: 15
    gocognit:
      min-complexity: 20
    revive:
      rules:
        - name: max-control-nesting
          arguments: [4]

formatters:
  enable:
    - gofmt
```

- The file is named `.golangci.yml`.
- `formatters` is required: golangci-lint v2 runs no formatter by default, so without it
  `make fmt` formats nothing.
- Adding a linter to an existing repo surfaces every old finding at once. Do it as its own change,
  not inside a feature branch.

## Makefile

Added to the skeleton in `SKILL.md` → "Makefile". `APP` and the `cmd/` path are the project's own;
the rest is the standard.

```makefile
.PHONY: build run clean test lint lint-fix fmt check release docker install-tools ensure-lint ensure-goreleaser

APP     := <app>
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS := -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(DATE)

# Pinned tools live in ./bin; versions come from the dotfiles, never from a global install
GOLANGCI_VERSION   := $(shell cat .golangci-lint-version)
GOLANGCI           := ./bin/golangci-lint
GORELEASER_VERSION := $(shell cat .goreleaser-version)
GORELEASER         := ./bin/goreleaser
KEEP_TOOLS         := golangci-lint goreleaser

# distroless images live on gcr.io; CI passes its own registry mirror instead
DOCKER_MIRROR ?= gcr.io/

build: clean ## Compile
	@go build -trimpath -ldflags "$(LDFLAGS)" -o bin/$(APP) ./cmd/$(APP)

run: build ## Run
	@./bin/$(APP) --help

clean: ## Clean build output (keeps the pinned tools in bin/)
	@[ ! -d bin ] || find bin -mindepth 1 -maxdepth 1 $(foreach t,$(KEEP_TOOLS),! -name "$(t)") -exec rm -rf {} +
	@rm -rf dist/

ensure-lint:
	@if [ ! -x "$(GOLANGCI)" ] || ! "$(GOLANGCI)" version 2>/dev/null | grep -q "$(GOLANGCI_VERSION:v%=%)"; then \
		curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b ./bin "$(GOLANGCI_VERSION)"; \
	fi

ensure-goreleaser:
	@if [ ! -x "$(GORELEASER)" ] || ! "$(GORELEASER)" --version 2>/dev/null | grep -q "$(GORELEASER_VERSION:v%=%)"; then \
		mkdir -p bin && \
		curl -sSfL "https://github.com/goreleaser/goreleaser/releases/download/$(GORELEASER_VERSION)/goreleaser_$$(uname -s)_$$(uname -m | sed 's/aarch64/arm64/').tar.gz" \
			| tar -xz -C bin goreleaser; \
	fi

install-tools: ensure-lint ensure-goreleaser ## Install the pinned tools to ./bin
	@echo "golangci-lint $(GOLANGCI_VERSION), goreleaser $(GORELEASER_VERSION) ready in ./bin"

test: ## Run tests
	@go test -v -race -count=1 -timeout 120s ./...

lint: ensure-lint ## Run linter (pinned version)
	@$(GOLANGCI) run ./...

lint-fix: ensure-lint ## Run linter with auto-fix
	@$(GOLANGCI) run --fix ./...

fmt: lint-fix ## Format code (lint + fix)
	@echo "Code formatted!"

check: fmt lint test ## Full local check (run before commit)
	@echo "All checks passed!"

release: ensure-goreleaser ## Package dist/linux_amd64.tar.gz as CI does (snapshot, nothing published)
	@$(GORELEASER) release --snapshot --clean --skip=publish

docker: release ## Build the image locally from dist/
	@docker build --platform linux/amd64 --build-arg CC_REGISTRY_MIRROR=$(DOCKER_MIRROR) -t $(APP):dev .
```

- `clean` deletes everything in `bin/` except `KEEP_TOOLS`. A plain `rm -rf bin/` also deletes the
  pinned tools, so the `make lint` after every build downloads them again — and fails offline. A
  project that installs another tool into `./bin` adds it to `KEEP_TOOLS`.
- Never call a global `golangci-lint` or `goreleaser`; `lint` and `release` go through `ensure-*`.
- Both tools are downloaded once from their GitHub releases; neither has an official mirror. On a
  slow link run the target with `HTTPS_PROXY` set — `curl` honors it. Do not swap in a third-party
  download mirror or fall back to a global install.
- Tests always run with `-race` and a `-timeout`.
- The version variables are `main.version`, `main.commit` and `main.date` (the `go` skill's CLI
  reference, "Version Info"); `.goreleaser.yaml` injects the same three.
- A library with no binary drops `build`, `run`, `release`, `docker` and the goreleaser lines.
- Optional extras: `generate` (buf), `migrate`, `dev-deps` / `dev-down` for local dependencies.

## .goreleaser.yaml

For a service packaged into an image. goreleaser only builds and archives; nothing is published
from it.

```yaml
version: 2

project_name: <app>

builds:
  - main: ./cmd/<app>
    binary: <app>
    env:
      - CGO_ENABLED=0
    goos:
      - linux
    goarch:
      - amd64
    flags:
      - -trimpath
    ldflags:
      - -s -w
      - -X main.version={{ .Version }}
      - -X main.commit={{ .ShortCommit }}
      - -X main.date={{ .Date }}

archives:
  # The Dockerfile takes dist/${OS_ARCH}.tar.gz, so the archive is named by platform alone
  - formats: ['tar.gz']
    name_template: "{{ .Os }}_{{ .Arch }}"

checksum:
  disable: true

changelog:
  disable: true
```

- `-trimpath` is required: without it the build machine's absolute paths, user name included, end
  up in the binary and in every log line that carries a source location.
- The tag must be one goreleaser accepts as a semantic version (`SKILL.md` → "Release tags").
- A tool released for download on GitHub needs more (several platforms, checksums, a changelog).
  Start from the config of a comparable public project instead of stretching this one.

## Dockerfile

The image only unpacks what CI built; it compiles nothing.

```dockerfile
ARG CC_REGISTRY_MIRROR
FROM ${CC_REGISTRY_MIRROR}distroless/static-debian13:debug-nonroot

WORKDIR /app

ARG OS_ARCH=linux_amd64
ADD --chown=nonroot:nonroot dist/${OS_ARCH}.tar.gz /app/
COPY --chown=nonroot:nonroot config/config.yaml /app/config/config.yaml

EXPOSE 8000 9000

ENTRYPOINT ["/app/<app>"]
```

- `CC_REGISTRY_MIRROR` is the build argument the CI image job passes; locally `make docker` sets
  it to the public registry.
- The image runs as `nonroot`, so everything copied in is `--chown=nonroot:nonroot`. A directory
  the process writes to is created and chowned in the Dockerfile; `/app` itself is not writable.
- Only the committed main config goes in. It holds no secret: those arrive as environment
  variables or a mounted `*.local.yaml` (the `go` skill's config reference).
- Do not set `TZ`. The container stays on UTC and a business timezone is explicit configuration,
  with `time/tzdata` imported in `main` (the `go` skill's time and timezone reference).
- Ports follow the `go` skill's baseline rules: HTTP 8000, gRPC 9000.
- A multi-stage Dockerfile that compiles is only for a repo with no pipeline artifact to unpack —
  for instance a platform that builds from source. Its builder is `golang:<minor>`.

### .dockerignore

An allowlist: the context is exactly what the Dockerfile copies.

```
**
!dist/*.tar.gz
!config/config.yaml
```

A denylist drifts every time a directory is added, and one stray entry ships `*.local.yaml` — the
file that holds the secrets.
