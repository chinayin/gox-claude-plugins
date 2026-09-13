# gox-claude-plugins

Team plugins for Claude Code, distributed through a single marketplace (`chinayin`). They load on demand and write nothing into your repo.

[中文说明](README.zh-CN.md)

## Plugins

| Plugin | Purpose |
|---|---|
| `gox-code-rules` | Team coding standards as Agent Skills (Go / frontend / shell / engineering). A skill activates while you edit matching files and reads only the reference file the current task needs. |
| `token-thrift` | Cheap-model subagents for token-heavy work: reads on Haiku, correctness-sensitive writes on Sonnet, the main agent only orchestrates. Raw material stays out of the main context. |
| `gox-guard` | Deterministic gates for irreversible actions Claude is about to take, one hook script per gate, nothing written into your repo. First gate, `secrets`: before `git push`, the commits not yet on any remote are scanned with [betterleaks](https://github.com/betterleaks/betterleaks) and a finding blocks the push. |
| `diagram-design` | Third-party ([cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design), MIT), referenced rather than copied; tracks the upstream default branch. Editorial diagrams (40 types) as standalone HTML/SVG plus import/export commands. Opt-in; not in the default template. Registry and intake checklist: [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md). |

Centralising standards here avoids the usual cost of copying them into every repo's `CLAUDE.md`: drift across repos, context bloat, and unclear ownership. The skills are in-session guidance and may not always trigger; final enforcement is `golangci-lint` / CI / PR review. `gox-guard` is the one deterministic piece: it runs an external scanner and can block a tool call, so it is documented separately below.

## Install

Per project (recommended, shared via git). Merge `templates/project-settings.json` into the repo's `.claude/settings.json` and commit. Collaborators who trust the repo are prompted to enable the plugins; scope is that repo only. Full config in [USAGE.md](USAGE.md).

Single machine:

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/plugin install gox-guard@chinayin
/plugin install diagram-design@chinayin   # optional, third-party
/reload-plugins
```

`gox-guard` additionally needs the scanner on the machine: `brew install betterleaks` (or `go install github.com/betterleaks/betterleaks@latest`). The plugin never installs it for you; until it is present, pushes from Claude are blocked with an install hint.

## gox-code-rules

| Skill | Invoke | Activates when | Content |
|---|---|---|---|
| Engineering | `/gox-code-rules:engineering` | session nudge + description (no file filter) | Karpathy guidelines: think first, keep it simple, surgical changes, goal-driven |
| Go | `/gox-code-rules:go` | Go tasks — nudge + description, model-invoked (`paths` declared, not load-bearing) | Go architecture + gin HTTP / cobra / gox-config / goose / time & timezone / scaffolding; detail in `references/`, read on demand |
| Frontend | `/gox-code-rules:frontend` | frontend tasks (same mechanism) | React / Vue / TS / JS / styling (skeleton; body TODO) |
| Shell | `/gox-code-rules:shell` | shell tasks (same mechanism) | bash/CLI scripts: stdout/stderr split, status prefixes, standard flags, exit codes, `test.sh` |
| Skill | `/gox-code-rules:skill` | writing or editing a SKILL.md (same mechanism) | naming (`object-action`, no version suffix), body language, no environment facts; adds only what the official skill-creator leaves open |

How to phrase requests so a skill triggers, and what to do when it doesn't: see [USAGE.md](USAGE.md).

## token-thrift

Offloads token-heavy work to cheaper-model subagents. The main agent only orchestrates; bulk material never enters its context, so it is not re-billed on later turns.

| Component | Invoke | Model | Role |
|---|---|---|---|
| cheap-reader | `subagent_type: cheap-reader` (or `@cheap-reader`) | Haiku | Read-only: read Lark/Feishu in full, wide searches, verification, log/long-doc analysis; returns a conclusion |
| careful-writer | `subagent_type: careful-writer` (or `@careful-writer`) | Sonnet | Correctness-sensitive writes, e.g. Lark/Feishu XML/blocks |
| delegate | `/token-thrift:delegate` | — | Policy: when to offload and which tier |

After install, the main agent decides whether to delegate from each agent's description; you can also name one explicitly, or force-load the policy with `/token-thrift:delegate`.

Rule of thumb: offload when the throwaway material a subagent must process is around 3k tokens or more. Keep it inline for small tasks, or when the main thread will reuse the material.

Agent and skill bodies are written in English (better for the model); this README and its Chinese version are for people.

## gox-guard

Deterministic gates for irreversible actions Claude is about to take. Each gate is one hook script under `plugins/gox-guard/hooks/`, registered side by side on the same events, prefixed `[gox-guard/<gate>]` in its messages, and skipped as a whole by `GOX_GUARD_SKIP=1`. What qualifies as a gate: a hard rule that can be decided deterministically, applied only to an outward, hard-to-undo action, writing nothing into the repo. Advisory checks belong in `gox-code-rules`; things only CI can decide stay in CI.

### Gate: secrets

Sits at the one moment a leaked credential becomes irreversible: the push. Everything before it (editing, staging, committing) stays untouched, so day-to-day coding is not slowed down.

| Event | What happens |
|---|---|
| Session start | Checks that `betterleaks` is on `PATH`. Present: silent. Missing: one line telling the model to ask you to install it. |
| Claude runs a Bash command containing `git … push` | Scans the commits on `HEAD` that are not on any remote (`--all` / `--mirror` widen this to every local branch). Nothing pending: allowed without scanning. Clean: allowed silently. Findings: the push is **denied**; the model gets one line per finding (rule, file:line, commit, fingerprint; capped at 10) and a two-sentence verdict rule. |
| Scanner (or `jq`) missing, or scanner failing | The push is denied with the reason, not silently allowed. A gate that fails open is no gate. |

The block message is deliberately short because it lands in the main agent's context, and it carries no manual: the model already knows git. What it tells the model:

1. Real secret: remove it from the offending commits and tell you it already exists in local history and should be rotated. Never allowlist a real secret.
2. False positive on one line: `# betterleaks:allow` comment on that line.
3. False positive already committed: append the fingerprint to `.betterleaksignore`. Recurring pattern (fixtures, examples): a path/regex allowlist in `.betterleaks.toml`. Both are ordinary committed files that show up in review.

Design choices worth knowing:

- **Push, not commit.** Commits are local and cheap to redo; gating them makes every edit-commit loop heavier and still misses `git add … && git commit …` in one command (a pre-commit scan sees the index before the add). At push time the range is fully determined.
- **No config required.** Without a config the scanner's built-in rules apply. A repo adds `.betterleaks.toml` / `.betterleaksignore` only when it first needs an allowlist; the plugin never writes them.
- **No version pinning.** Only the pending range is scanned, so a newer rule set can never turn old commits red. Use whatever `brew` gives you.
- **Always redacted, never validated.** `--redact` is always on (findings enter the model's context and transcript); the scanner's online validation feature is never enabled (it would send suspected secrets to vendor APIs).
- **Scope.** It only sees pushes Claude runs. Pushes you type in a terminal, and CI, are outside it: the repo's CI remains the last hard gate.
- **Bypass.** `GOX_GUARD_SKIP=1` in the environment skips the gate. The model is told to use it only when you explicitly ask.

## Development

- Deps and tests: `make deps` (jq + bats-core), `make validate` (jq-check every manifest and the template), `make test` (all bats).
- Test layout: central `tests/` holds cross-plugin checks (`manifests` / `skills` / `template`, looping `plugins/*`, so new plugins are covered automatically); plugin-specific tests live under `plugins/<name>/tests/`. `make test` runs `bats tests plugins/*/tests`.
- Trigger/hit rate (does the model load a skill, does it delegate) is not a bats gate; it is probabilistic. Evaluate with the skill-creator eval flow (with-plugin vs baseline). `make eval` has the pointer.
- `gox-guard` is fully deterministic and its bats cover it with a stub scanner (clean / findings / missing / failing). To exercise the real binary point `GOX_GUARD_BIN` at a `betterleaks` build and feed the hook a PreToolUse JSON on stdin.
- Adding a language or domain: one skill per language in the same plugin, each with `description` + `paths` + `references/`. See `docs/DESIGN.md`.

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
