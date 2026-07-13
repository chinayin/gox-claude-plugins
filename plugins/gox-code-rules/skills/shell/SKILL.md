---
name: shell
description: Team shell/bash scripting standards — how to structure a script and its CLI: argument/flag parsing, stdout-vs-stderr, status output (no emoji or color), exit codes, and a self-test harness. Use whenever you write, edit, or design any shell script or command-line tool in this repo — .sh/.bash files, helper/CI/build/automation scripts, even tiny one-offs — regardless of whether the user says "standards".
paths: "**/*.sh, **/*.bash"
---

# Team Shell Standards

Conventions for writing shell scripts in this repo, distilled from mature high-star CLIs
(cargo / git / gh / docker / kubectl) and the [Command Line Interface Guidelines](https://clig.dev/).
**Reply and write code comments in Chinese.**

## Core rules

- Start every script with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Always quote expansions (`"$var"`, `"${arr[@]}"`); keep `[ ]` / `[[ ]]` usage consistent.
- Handle secrets/credentials with least privilege — e.g. a generated private key gets `chmod 600`.
- Give destructive actions a guard: refuse by default, require an explicit `--force` (or similar).
- Document exit codes and keep their meaning stable (see below).
- Ship a `test.sh` next to any non-trivial script.

## Output: stdout vs stderr

- **stdout = data** — the script's actual product (a key, a JSON document, an ID, a path). Only this
  belongs on stdout, so `... --json | jq`, `... | pbcopy`, and `$(...)` stay clean.
- **stderr = messages** — errors, warnings, progress, diagnostics. This is out-of-band info, not the
  result. When in doubt, send it to stderr.

## Status output: plain text, no emoji, no color

Scripts here are driven by agents / CI, where color carries no meaning and emoji reads as a toy. Use
plain-text prefixes; there is then nothing to gate on `NO_COLOR` / TTY detection.

- Errors: `错误: <message>` to stderr, then a non-zero exit.
- Warnings: `警告: <message>` to stderr.
- Test results: `[PASS]` / `[FAIL]` (aligns with Go test `--- PASS/FAIL` and TAP `ok/not ok`).

Do **not** print log-level labels (`ERR`, `WARN`, `INFO`, `DEBUG`) in normal operation — only under
`-v/--verbose` (clig.dev).

```bash
die()  { echo "错误: $*" >&2; exit 1; }
warn() { echo "警告: $*" >&2; }
vlog() { [ "$VERBOSE" -eq 1 ] && echo "verbose: $*" >&2 || true; }   # diagnostics to stderr only
```

## Standard flags

| Flag | Meaning |
|---|---|
| `--json` | Machine-readable output; **pure** JSON on stdout, nothing else. |
| `--dry-run` | Print the plan; make no changes. |
| `-v`, `--verbose` | Extra diagnostics, **to stderr only** (never pollute stdout / JSON). |
| `--` | End of options; every following token is a positional argument. |
| `--version` | Print the version and exit 0. |
| `-h`, `--help` | Print usage to stdout on request (to stderr after a usage error). |

Flag names use kebab-case (`--out-dir`); bool flags take no value (`--force`, not `--force=true`);
add a short form only for high-frequency flags; reject unknown options with a usage message and exit 1.

```bash
    -v|--verbose) VERBOSE=1; shift ;;
    --) shift; while [ $# -gt 0 ]; do set_name "$1"; shift; done ;;
    -*) usage >&2; die "未知选项: $1" ;;
```

## Exit codes

Give exit codes documented, stable meaning and list them in the help text. A common set:

- `0` success
- `1` usage error / runtime failure / target already exists
- `2` precondition not met (a required tool or input is absent)

Let the underlying tool's own non-zero code surface when it is the thing that failed.

## Test harness (`test.sh`)

Ship a hermetic, self-cleaning self-test beside any non-trivial script:

```bash
#!/usr/bin/env bash
set -uo pipefail
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

# ... assertions writing only into $TMP ...

echo "结果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

Cover the happy path **and** the guardrails (bad arguments, overwrite refusal, precondition
failures). When a feature has two code paths (e.g. two backend tools), test both, and skip with a
visible message when a path's dependency is unavailable rather than silently passing.

> These are in-session **soft guidance**; the final enforcement is the repo's shellcheck / CI / PR review.
