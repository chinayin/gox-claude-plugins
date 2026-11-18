---
name: bashly
description: >-
  Team standards for a CLI built with bashly (the bash CLI generator) — project layout, settings.yml, the committed generated script, thin command files over testable lib functions, flags shared across subcommands, static checks, and bats tests. Use whenever the project contains a `bashly.yml` or the user asks for bashly: editing `bashly.yml` / `settings.yml`, writing `src/*_command.sh` or `src/lib/*.sh`, regenerating the script, or scaffolding a new bashly CLI. Hand-written scripts stay with the `shell` skill; never convert one to bashly unless the user asks.
paths: "**/bashly.yml"
---

# Team Bashly Standards

Rules for a CLI generated with [bashly](https://bashly.dev). They apply only inside a bashly
project: one that has a `bashly.yml`, or one the user asked to build with bashly. Choosing bashly is
the user's call — when a hand-written script has grown, you may suggest bashly in one sentence, but
keep following `shell` and do not convert it.

## Relation to the `shell` skill

Load the `shell` skill too, before you write anything: its output and safety rules govern the code
under `src/`, and hand-written scripts in the same repo (say `scripts/release.sh`) follow it
unchanged. For `src/`, it applies in part:

| `shell` section | In a bashly project |
|---|---|
| Output: stdout vs stderr; Status output; the brace, secrets and `--force` rules in Core rules | Apply |
| Standard flags | Same names and meaning, declared in `bashly.yml` instead of parsed by hand |
| Exit codes | Apply to your own code. Framework errors (unknown command or option, missing argument, missing `dependencies` entry) go to stderr and exit 1; give them the `Error:` prefix through `bashly-strings.yml` (see "Settings") |
| Shebang and `set -euo pipefail` | Skip — partials have neither; `strict: true` puts the `set` line in the generated script |
| Hand-written `while`/`case` parsing | Skip — generated |
| Test harness (`test.sh`), and the `[PASS]` / `[FAIL]` line in Status output | Skip — bats prints TAP; see "Tests" |

## Layout

The default, for a single CLI:

```
src/bashly.yml          # command declaration
src/bashly-strings.yml  # framework message overrides
settings.yml
src/<cmd>_command.sh    # one per subcommand
src/lib/*.sh            # functions, unit-testable
<name>                  # generated script, committed
tests/*.bats
```

A project may lay this out differently through `source_dir`, `target_dir` and `extra_lib_dirs` —
say two CLIs sharing one lib directory, each with its own settings file selected by
`BASHLY_SETTINGS_PATH`. Follow the project's settings; the rules below apply to either shape.

## Tooling

A project that pins a bashly version (a Makefile target, a versioned image, a Gemfile) is generated
its way, with exactly that version. Otherwise use `bashly` from PATH, and without it the image,
which generates byte-identical output for the same version:

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/app" dannyben/bashly generate
```

With neither available, stop and tell the user; do not install anything yourself. With no pin, use
whatever version the machine or the `latest` image provides.

The generated script needs bash >= 4.2 and exits 1 under macOS's stock `/bin/bash` 3.2. Its shebang
is `#!/usr/bin/env bash`, so a newer bash earlier on PATH is enough.

## Settings

```yaml
# settings.yml
env: production                     # plain `bashly generate` builds the script to commit;
                                    # the default is a development build
strict: true                        # `set -euo pipefail`; the default is `set -e` only
enable_deps_array: never            # these two arrays are unused by default and trip shellcheck
enable_env_var_names_array: never   # SC2034; drop a line when your code reads that array
```

Run `bashly add strings` once. In the `src/bashly-strings.yml` it creates, prefix every message
under "Error messages" with `Error: ` and delete the keys you leave unchanged, so a framework error
reads like one of your own (`shell`, "Status output").

Do not run `bashly add colors` or set `usage_colors` — team output carries no color (`shell`,
"Status output").

## Generated script

- Commit what `bashly generate` produces under `env: production`; that build drops the
  development-only helpers (`inspect_args`, view markers). For a debugging build pass
  `--env development` and do not commit it. Never edit the script by hand — the next generate
  overwrites the edit.
- Regenerate whenever `src/` or `settings.yml` changes, and commit the script with its source.
- Line 2 of the script records the generator version. Do not regenerate with an older bashly than
  that: output differs between versions (2.0.0 changed how `--` is handled), so a downgrade
  silently reverts behaviour. A diff that comes only from a newer version is expected — commit it.
- A project that pins the version keeps a regenerate-and-diff check in CI (`git diff --exit-code`
  after generating). Without a pin there is no such check, since a different version would trip
  it; the tests run the committed script, so a stale one fails there.

## Code

- Keep a command file thin: read `args`, call lib functions, print. Put the logic in `src/lib/*.sh`
  functions that take explicit parameters and never read the global `args`, so bats can source and
  call them.
- Read an optional value as `${args[--x]:-}`. Under `strict`, an unset key kills the script with
  `unbound variable`.
- Declare a shared flag once and reference it under each subcommand: a YAML anchor inside one
  file, or `- import: src/flags/json.yml` of a one-flag file when commands are nested or two CLIs
  share it. A root-level flag is accepted only before the subcommand: `tool --verbose list` works,
  `tool list --verbose` is an invalid option.

```yaml
commands:
- name: list
  flags:
  - &json
    long: --json
    help: Machine-readable output
- name: apply
  flags:
  - *json
```

```bash
# src/list_command.sh
limit="${args[--limit]:-10}"
if [[ -n "${args[--json]:-}" ]]; then
  items_list "${limit}" | items_to_json
else
  items_list "${limit}"
fi
```

## Static checks

- Run shellcheck on the generated script. A partial on its own has no shebang and reports SC2154
  (`args` referenced but not assigned).
- Run the brace gate from `shell` ("Test harness") recursively over `src/`.

## Tests

Use bats under `tests/`. Write plain `run` and `[ ]` by default; a project whose tests already
load bats-assert / bats-support keeps using them. A file that uses `run --separate-stderr` or `run -N` declares `bats_require_minimum_version 1.5.0`.

- **Unit**: source `src/lib/*.sh` and call the functions.
- **Contract**: run the generated script. Cover at least:
  - `--help` exits 0;
  - an unknown option exits 1;
  - stdout carries only data;
  - `--json` output passes `jq -e .`;
  - `--dry-run` changes nothing;
  - a destructive action refuses without `--force`.

```bash
bats_require_minimum_version 1.5.0
CLI="$BATS_TEST_DIRNAME/../mytool"

@test "unknown option exits 1 with the message on stderr" {
  run --separate-stderr "$CLI" list --nope
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
```

Isolate every test: point `HOME` and `TMPDIR` at `$BATS_TEST_TMPDIR`, replace external commands
(docker, kubectl, curl) with stub scripts placed first on PATH, and do not touch the network — a
missing stub must never reach real credentials or a real service. A stub is a hand-written script
like any other: give it the `shell` header (`#!/usr/bin/env bash`, `set -euo pipefail`), so a test
environment that forgot to set one of its variables fails loudly.

> These are in-session **soft guidance**; the final enforcement is the repo's shellcheck / tests / PR review.
