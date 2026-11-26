# scaffold skill evals

How to run: [../README.md](../README.md).

## Cases

| Case | The request | What the checks look for |
|---|---|---|
| `go-service` | A Go service on GitLab with shared CI templates gets its release files: goreleaser config, Dockerfile, `.dockerignore`, `release` and `docker` targets, a lint config | `-trimpath` and the three `main.*` variables, no invented `.goreleaser-version` (the CI image is out of reach, so the gap is reported instead), the pinned goreleaser in `./bin`, a `clean` that keeps the tools, a Dockerfile that compiles nothing and sets no `TZ`, an allowlist `.dockerignore`, `.golangci.yml` with a formatter and the limits, the CI paths in `.gitignore`, no `.github/`, the pipeline left on the shared templates |
| `github-ci` | A Go library on GitHub gets CI for lint, test and build | Versions read from `go.mod` and `.golangci-lint-version`, `permissions`, `concurrency` and a timeout in every workflow, actions on a major tag, tests through `make`, no `.gitlab-ci.yml` |

Both fixtures are small synthetic projects shaped like the real ones. A real project is not used:
a fixture is committed to this repository.

`triggers.tsv` holds seven requests that must load `scaffold` (two of them never name a
scaffold file: a Makefile bug and a question about a tag), three Go code changes that must load
`go` alone (one asks for "the latest gin", next to the scaffold row that asks for the latest
golangci-lint), one script that must load `shell` alone, and two questions that must load none.

## Observation: 2026-11-26

Working tree of `worktree-feat+scaffold-skill` (plugin 0.10.0, uncommitted), `claude-haiku-5-5`.
One run per arm for the cases, so those are single samples, not rates.

| Case | With the plugin | Baseline | What the baseline missed |
|---|---|---|---|
| `go-service` | 14/14 | 5/13 | No version dotfile and a global `goreleaser`; targets named `package` and `docker-build`; `clean` still `rm -rf bin/`; a Dockerfile that compiles; a denylist `.dockerignore`; a lint config without the limits; `.gitignore` without the CI paths |
| `github-ci` | 11/11 | 9/10 | Action versions written from memory: `actions/checkout@v4` and `actions/setup-go@v5`, both at v7 by then |

- The baseline column counts only the checks that apply to it; the skill-loading check skips.
- Both cases loaded `scaffold` and nothing else.
- `github-ci` shows the skill doing little on this model: the baseline already wrote permissions,
  a concurrency group, timeouts and `go-version-file`, and ran lint and tests through `make`.
- In the first `go-service` run the model could not find the CI image — the fixture's template
  project does not exist — and took the goreleaser version from the `goreleaser` installed on the
  machine. The skill said where the value comes from but not what to do when that source is out of
  reach. It now says to leave the file unwritten and report it, and the check asks for exactly
  that. Two more runs with the rule in place: 14/14 both, no version file, the gap reported.
- Trigger queries, first round: 36/36 sessions matched (the 12 queries the table held then, 3
  sessions each).
- The `shell` and `bashly` queries were rerun on the same model to see whether the new `scaffold`
  route pulls them off course: `shell` 12/12, `bashly` 11/12. The miss was "写一个发布脚本
  release.sh", which loaded `scaffold` next to `shell` in one of two sessions.
- The reminder's `scaffold` line was reworded twice because of that. "a release or a tag" became
  "packaging a release, choosing a tag" with "a script stays with `shell`" added; that fixed the
  release script (6/6) but "把 golangci-lint 升到最新版" dropped from 3/3 to 5/7. Adding "pinning or
  upgrading a build tool (golangci-lint, goreleaser)" brought it back.
- Final wording, six sessions per query: the lint upgrade 6/6, "引入最新版的 gin" 6/6 loading `go`
  alone, the release script 5/6 — it still loads `scaffold` next to `shell` now and then. The
  other eleven rows of this table were last run on the first rewording (11/11, one session each)
  and not again on the final one.
- An eval session reads the whole machine; only its writes are sandboxed. In `go-service` the
  model ran `glab` and searched the home directory for the template project.
