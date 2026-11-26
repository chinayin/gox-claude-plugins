# mock-secret rule evals

How to run: [../README.md](../README.md).

This directory is not a skill. The rule is one line in the session reminder
(`hooks/session-nudge.sh`): a fake password, token or key starts with `mock-`. The cases ask for
files that need concrete fake credentials and never mention the rule.

## Cases

| Case | The request | What the checks look for |
|---|---|---|
| `compose-env` | A `docker-compose.yml` and a `.env.example` filled in so that it runs as copied | Literal credential values exist, each starts with `mock-`, and a scan with the push gate's default config (`gox-guard/lib/betterleaks.toml`) reports nothing |
| `seed-script` | A script that creates a test admin through a local API, credentials written in the script | The same three checks on the script |

The scan check needs betterleaks and skips without it. There is no `triggers.tsv`: no skill is
expected to load for the rule.

## Observation: 2026-11-26

`main` at 4b253d0 plus this directory (plugin 0.10.0), `claude-haiku-5-5`, betterleaks 1.10.1.
Three sessions per arm.

| Case | With the plugin | Baseline | What the baseline wrote |
|---|---|---|---|
| `compose-env` | 3/3 sessions passed all checks | 0/3 | `dev-postgres-password-123`, `local_pg_password_change_me` and the like; every session had findings in the gate scan |
| `seed-script` | 3/3 | 0/3 | `DevAdmin123!`, `dev-admin-token-change-me` and the like; every session had findings in the gate scan |

- With the plugin every literal credential in all six sessions started with `mock-`
  (`mock-password`, `mock-redis-password`, `mock-sms-token-1`).
- All six baseline sessions would have been stopped at push: the rule is what keeps these files
  out of triage.
- `compose-env` loaded `go` in 3/3 sessions and `scaffold` in 2/3, although the task touches no Go
  file and none of the scaffold files. The reminder routes "configuration, environment variables,
  or secrets" to `go`; for a compose file that is a skill body read for nothing.
- `seed-script` loaded `shell` only.

## Observation: 2026-11-26, after the `go` route was narrowed (plugin 0.10.2)

The reminder now sends configuration, environment variables and secrets to `go` only when Go code
loads them, and says a config file with no Go change needs no skill. Same model, three sessions
per row.

| What ran | `go` loaded | `scaffold` loaded | Result |
|---|---|---|---|
| `compose-env` with the plugin | 0/3 (was 3/3) | 0/3 (was 2/3) | 3/3 passed all checks, with no skill loaded |
| The `compose-env` prompt as a trigger query | 0/3 | 1/3 | — |
| "Write a `config.example.yaml`" as a trigger query | 0/3 | 0/3 | — |
| Five Go tasks as trigger queries: the three `go` rows of `scaffold/triggers.tsv`, reading `PORT` from the environment, reading an API token from config | 15/15, `go` alone | 0/15 | — |

- The rule holds without any skill: the `mock-` line is in the reminder itself.
- A compose session cost about a quarter less than before (mean $0.0071 against $0.0095).
- The trigger queries beyond the three existing `go` rows were run from a scratch file and are not
  in a `triggers.tsv`.
