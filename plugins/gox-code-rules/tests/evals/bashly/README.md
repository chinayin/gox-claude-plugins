# bashly skill evals

How to run: [../README.md](../README.md).

## Cases

| Case | The request | What the checks look for |
|---|---|---|
| `new-cli` | "用 bashly 做…" a three-subcommand CLI, two of them with `--json` | Layout, `strict: true`, no colors, committed production script identical to a fresh generate, shellcheck, `--json` declared once and shared by anchor or import, framework errors prefixed with `Error:`, optional flags read with a default, passing bats tests, a delete guard |
| `add-command` | Add a subcommand to the project in `fixture/` and add `--dry-run` to its hand-written `scripts/release.sh`; bashly is not mentioned | `bashly` loads because of `bashly.yml`, the script is regenerated and not hand-edited, the anchor is reused, bats tests cover the new command, the hand-written script still follows `shell` |

`triggers.tsv` holds three requests that must load `bashly` (one names it, two only sit in a
project with a `bashly.yml`), two that must load `shell` alone (a script with two flags, and a
five-subcommand CLI that does not mention bashly), and one question about bashly that must load
neither.

## Observation: 2026-11-18

Working tree of `feat/bashly-skill` (plugin 0.9.0, uncommitted), `claude-sonnet-5-5`,
bashly 2.0.0, shellcheck 0.11.0, bats 1.14.0. One run per arm, so these are single samples, not
rates.

| Case | With the plugin | Baseline | What the baseline missed |
|---|---|---|---|
| `new-cli` | 13/13 | 1/11 | No `strict`, script generated into `bin/`, no anchor, no lib, no bats tests |
| `add-command` | 13/13 | 9/11 | Committed script differed from a fresh generate; no test for the new command |

- The baseline column counts only the checks that apply to it; the skill-loading checks skip.
- `new-cli` baseline: the script landed in `bin/notes`, so the behaviour checks that look for
  `./notes` failed along with the layout check. Its 1/11 overstates the gap.
- Both cases loaded `bashly` and `shell` when run with the plugin.
- Trigger queries: 18/18 sessions matched. In 3 of the 9 sessions that had to load `bashly`,
  `shell` had not been loaded by the first file write. The skill's opening instruction was
  reworded from "Load `shell` as well" to "Load the `shell` skill too, before you write anything";
  rerunning those 9 sessions loaded both skills in 9/9. The two cases above ran before that
  rewording.
- The first trigger run used the default permission mode and took about nine minutes per session
  for the first query; the cause was not established. `run-trigger.sh` now uses the same sandboxed
  permissions as `run-case.sh` and stops a session after 180 seconds; the full set then took
  seven minutes.

## Observation: 2026-11-19

The skill changed after a review of a real two-CLI bashly project: framework errors get the
`Error:` prefix through `bashly-strings.yml`, a shared flag may be an `import:` as well as an
anchor, the layout is a default rather than a requirement, and a project's pinned bashly version
wins over the newest one. Same environment as above, one run per case, with the plugin only.

| Case | With the plugin |
|---|---|
| `new-cli` | 14/14 |
| `add-command` | 13/13 |

- `new-cli` gained the `Error:` prefix check; the run from 2026-11-18, made before the rule
  existed, fails exactly that check. The baseline from that day passes 3 of the 12 checks that
  apply to it.
- The "optional flags are read with a default" check used to flag every `${args[--x]}` without
  `:-`. It now reads `bashly.yml` and ignores flags that are required or declare a default; the
  reviewed project reads five such flags directly and no longer trips it.
- The fixture carries a `bashly-strings.yml` so that it follows the updated skill.
- Later the same day the skill moved the production switch from the command line into
  `settings.yml` (`env: production`), because the reviewed project had committed development
  builds by leaving the flag out. `new-cli` checks the setting; a rerun passed 14/14.
