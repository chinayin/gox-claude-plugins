# Skill evals

Manual evaluation of the `shell` and `bashly` skills with a real model. It is separate from
`make test`: a model run costs money and differs each time, so Bats only grades what a run
produced. `../evals.bats` covers the two runner scripts with a stub model and does run in
`make test`.

One directory per skill; each holds its cases, its trigger queries and its results:

```
run-case.sh  run-trigger.sh  helpers.bash
shell/   glue/  cleanup/  multi-command/   triggers.tsv  README.md
bashly/  new-cli/  add-command/            triggers.tsv  README.md
```

A case is a `prompt.md` (what a user would type), an optional `fixture/` (the project the model
starts in) and a `checks.bats` that grades the result.

## Run a case

```bash
OUT="$(./run-case.sh shell/cleanup /tmp/eval/cleanup-with)"      # with the plugin
EVAL_OUT="$OUT" bats shell/cleanup/checks.bats

OUT="$(./run-case.sh --baseline shell/cleanup /tmp/eval/cleanup-base)"   # without it
EVAL_OUT="$OUT" bats shell/cleanup/checks.bats
```

A check that passes both with and without the plugin shows the rule behind it is not doing any
work for that case. The skill-loading checks skip themselves on a baseline run.

`checks.bats` executes what the model wrote, outside any sandbox. Read the generated scripts
before grading.

## Run the trigger queries

```bash
./run-trigger.sh shell/triggers.tsv
./run-trigger.sh --runs 5 bashly/triggers.tsv
```

Each row is `expect`, `fixture`, `query`. A session is stopped the first time the model writes a
file, and the skills loaded before that are compared with `expect`: `shell` (and `bashly` must not
load), `bashly`, or `none`.

## What a run is

- Model: `sonnet` unless `EVAL_MODEL` is set. A trigger rate measured on one model does not carry
  over to another.
- `--setting-sources project`: user-level settings are ignored, so the plugins and personal skills
  installed on the machine take no part. Only this branch's plugin is loaded.
- The model's shell commands are sandboxed to its working directory and `TMPDIR`.
- Claude Code only. Codex, Cursor and pi load the same skill files but are not exercised here.
