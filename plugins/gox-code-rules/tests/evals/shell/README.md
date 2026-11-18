# shell skill evals

How to run: [../README.md](../README.md).

## Cases

| Case | The request | What the checks look for |
|---|---|---|
| `glue` | A one-purpose script that prints the branch and last commit | Team header, shellcheck, English output, no flags nobody asked for, no bashly |
| `cleanup` | Delete `*.log` files older than N days | Refuses without a confirmation flag, `--dry-run`, `--help`, exit 1 with `Error:` on a bad option, a passing `test.sh` |
| `multi-command` | A four-subcommand CLI in bash; bashly is not mentioned | Stays hand-written, team header, shellcheck, `Error:` on a bad subcommand, a passing `test.sh` |

`triggers.tsv` holds four script-writing requests that must load `shell` alone (one of them a
four-subcommand CLI), and two that must load neither skill: a question about bash, and a Python
task.

## Observation: 2026-11-18

Working tree of `feat/bashly-skill` (plugin 0.9.0, uncommitted), `claude-sonnet-5-5`,
shellcheck 0.11.0. One run per arm, so these are single samples, not rates.

| Case | With the plugin | Baseline | What the baseline missed |
|---|---|---|---|
| `glue` | 8/8 | 6/7 | Printed Chinese labels |
| `cleanup` | 11/11 | 4/10 | No delete guard, no `--dry-run`, no `--help`, no `Error:` prefix, no `test.sh` |
| `multi-command` | 9/9 | 6/8 | No `Error:` prefix, no `test.sh` |

- The baseline column counts only the checks that apply to it; the skill-loading check skips.
- The first `multi-command` prompt did not name a language and the baseline wrote Python. The
  prompt now says "用 bash 写"; the row above is the rerun of both arms.
- With the plugin, `glue` came out at 18 lines with no flags, and every case loaded `shell` only.
- Trigger queries: 18/18 sessions matched (6 queries, 3 sessions each).
