# GitHub Actions

For a repo whose remote is GitHub. A workflow runs what the `Makefile` runs and reads the same
version files, so CI and a developer's machine agree. Tests go through `make test`; lint uses the
golangci-lint action, which reads `.golangci-lint-version` and annotates the pull request.

## Every workflow

```yaml
on:
  push:
    branches:
      - main
  pull_request:

permissions:
  contents: read

concurrency:
  group: <workflow-name>-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

- `branches` names the repo's actual default branch (new repos: `main`). A workflow that lists a
  branch the repo does not have never runs.
- `permissions` is declared in every workflow and starts at `contents: read`; a job that needs
  more widens it for that job only.
- The `concurrency` prefix is a literal, never `${{ github.workflow }}`: inside a called workflow
  that context is the caller's name, both sides get the same group, and the run deadlocks.
- Every job sets `timeout-minutes` — a ceiling against a hung job, not an expected duration.
- No version is written into a workflow. Go comes from `go.mod` (`go-version-file`), golangci-lint
  from `.golangci-lint-version` (`version-file`).
- Actions are pinned to a major tag, looked up before writing (`SKILL.md` → "Versions"). The majors
  in the templates below were current when this file was written; check them.

## Go repo

Three workflows, each with the header above. `.github/workflows/lint.yml`:

```yaml
name: Lint

permissions:
  contents: read
  checks: write

jobs:
  golangci:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout code
        uses: actions/checkout@v7

      - name: Set up Go
        uses: actions/setup-go@v7
        with:
          go-version-file: go.mod

      - name: Run golangci-lint
        uses: golangci/golangci-lint-action@v9
        with:
          version-file: .golangci-lint-version
```

`.github/workflows/test.yml`:

```yaml
name: Test

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - name: Checkout code
        uses: actions/checkout@v7

      - name: Set up Go
        uses: actions/setup-go@v7
        with:
          go-version-file: go.mod

      - name: Run tests
        run: make test
```

`.github/workflows/build.yml`:

```yaml
name: Build

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout code
        uses: actions/checkout@v7

      - name: Set up Go
        uses: actions/setup-go@v7
        with:
          go-version-file: go.mod

      - name: Build
        run: go build -v ./...

      - name: Verify modules
        run: go mod verify
```

## Shell repo

One workflow, `.github/workflows/ci.yml`, with the header above:

```yaml
name: ci

jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout
        uses: actions/checkout@v7

      - name: Install shellcheck
        run: sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck

      - name: make check
        run: make check
```

A test that needs real machines, a full install or several architectures goes in its own
`e2e.yml`, started by `workflow_dispatch` only.

## Releases

A release workflow runs on a `v*` tag, calls the CI workflow first (`workflow_call`) and publishes
only when it is green. It derives the version from the tag and fails on a tag that is not
`vX.Y.Z`.
