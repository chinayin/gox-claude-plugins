# GitLab CI

For a repo whose remote is GitLab and whose pipeline is assembled from the organization's shared
CI templates. The templates own the jobs; the project's `.gitlab-ci.yml` only selects and
configures them.

## .gitlab-ci.yml is copied, not written

- Start from the Go example in the template project — the one the `include:` of a sibling service
  points at. Do not hand-write a pipeline and do not copy job bodies into the project.
- Read the template project before changing anything: which variables a job takes, which rules it
  presets, which files it expects. Do not guess a variable name.
- Adjust behaviour through the variables and the `rules` hooks the templates expose. Overriding a
  job's `script` forks it from every later fix to the template; do it only for something the
  template cannot express, and say why in a comment.

## The CI environment is prebuilt

Jobs run in a CI image that already contains Go, golangci-lint and goreleaser. The project selects
the image through the Go-version variable; the tools come with it.

- Do not install or upgrade a tool inside a job. Every run would download it again, and runners
  may not reach the public internet at all.
- Do not set a tool-version variable in the project. With the tool already in the image the
  variable is not consulted, and the pipeline reads as pinned to a version it does not run.
- `.golangci-lint-version` and `.goreleaser-version` must equal what the image ships, so that
  `make lint` and `make release` behave locally as they do in CI. Read the versions from the
  image's labels — no pull needed:

  ```bash
  docker buildx imagetools inspect <ci-image> --format '{{json .Image}}' \
    | jq '[.. | .Labels? // empty][0]'
  ```

  The image name is in the template project's variables.
- When the image cannot be inspected — its name or the registry is out of reach — do not fill a
  version file from anywhere else: not from the tool installed on this machine, not from the latest
  release. Leave the file unwritten and tell the user which value is missing and that it comes from
  the CI image.
- Upgrading a tool means moving to an image that ships the newer release: change the Go-version
  variable and both dotfiles in one commit.
- The Go patch release is the image's too. It must be at or above the `go` line in `go.mod`; the
  images run with `GOTOOLCHAIN=local`, so nothing is downloaded to make up a difference.

## What the build job expects

| The project provides | The job does |
|---|---|
| `.goreleaser.yaml` | Runs goreleaser — a release on a tag, a snapshot on a branch |
| Otherwise a `release` target in the `Makefile` | Runs `make release` |
| `dist/<os>_<arch>.tar.gz` from either | Hands it to the image job as an artifact |
| A root `Dockerfile` | Builds it with the repo as context and pushes it, tagged with the branch or tag name |

- The jobs write caches and build metadata into the work tree. They are in the Go `.gitignore`
  block (`references/go.md`); leave one out and goreleaser stops on a dirty tree.
- `.dockerignore` must let `dist/` through — the Dockerfile takes the binary from it.

## Pipeline shape

- Merge requests run the checks (lint and test) and build nothing.
- Environment branches and release tags build the archive and the image. They must be protected:
  the build and image jobs skip an unprotected ref.
- A tag pipeline skips the checks; the commit already passed them on its way in.
- The test job runs with `-race`, like `make test`.
- A tag follows the service scheme in `SKILL.md` → "Release tags".
