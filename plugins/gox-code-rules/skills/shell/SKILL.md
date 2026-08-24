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
- Exception — a **Claude Code hook script** must fail open: `set -u` only (no `-e`/`pipefail`),
  and exit 0 on every path; a hook's non-zero exit disrupts the session.
- Exception — a **test harness** (`test.sh`) uses `set -uo pipefail` without `-e`: a failing
  assertion is a counted result, not a fatal error.
- Always quote expansions (`"$var"`, `"${arr[@]}"`); keep `[ ]` / `[[ ]]` usage consistent.
- In a Chinese message, **brace** the expansion (`"${var}"`). A bare `$var` immediately followed by
  a non-ASCII character (`（`, `：`, `，`, a Han character…) swallows those bytes into the variable
  name: with `set -u` the script dies (`V?: unbound variable`), without it the value silently
  vanishes along with that character. This standard mandates Chinese messages, and those messages
  live on error paths a normal run never reaches — so it passes every smoke test and fails in
  production. Reproduces on bash 3.2.57 and 5.3.9 under a UTF-8 locale; `LC_ALL=C` masks it, so CI
  can stay green while the dev box dies. Special params (`$*`, `$1`, `$#`) are immune.
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

`$*` above is safe (a space follows it); the **call sites** are where the brace rule bites:

```bash
die "kubeconfig 不存在：${KCFG}（用 KUBECONFIG 指定）"    # 裸写 $KCFG（ 会被当成一个变量名
echo "共 ${count} 条 / 耗时 ${elapsed} 秒"
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

Note: this table deliberately differs from the common getopts/bash convention (which uses 2 for
usage errors); within team repos this table is authoritative.

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

Gate the brace rule there too — one line, works with both BSD and GNU grep:

```bash
# 揪出 `$VAR` 后面紧跟非 ASCII 的写法；C locale 下 [^ -~] 就是"非可打印 ASCII"
if LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' *.sh; then
  echo "错误: 上面这些 \$VAR 紧跟了非 ASCII 字符，改用 \${VAR}" >&2
  exit 1
fi
```

shellcheck does **not** flag this by default (verified with 0.11.0); `shellcheck -o SC2250` does,
but it flags every bare `$var` whether or not non-ASCII follows.

> These are in-session **soft guidance**; the final enforcement is the repo's shellcheck / CI / PR review.
