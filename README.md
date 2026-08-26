# gox-claude-plugins

Team plugins for Claude Code, distributed through a single marketplace (`chinayin`). They load on demand and write nothing into your repo.

[中文说明](README.zh-CN.md)

## Plugins

| Plugin | Purpose |
|---|---|
| `gox-code-rules` | Team coding standards as Agent Skills (Go / frontend / shell / engineering). A skill activates while you edit matching files and reads only the reference file the current task needs. |
| `token-thrift` | Cheap-model subagents for token-heavy work: reads on Haiku, correctness-sensitive writes on Sonnet, the main agent only orchestrates. Raw material stays out of the main context. |

Centralising standards here avoids the usual cost of copying them into every repo's `CLAUDE.md`: drift across repos, context bloat, and unclear ownership. The skills are in-session guidance and may not always trigger; final enforcement is `golangci-lint` / CI / PR review.

## Install

Per project (recommended, shared via git). Merge `templates/project-settings.json` into the repo's `.claude/settings.json` and commit. Collaborators who trust the repo are prompted to enable the plugins; scope is that repo only. Full config in [USAGE.md](USAGE.md).

Single machine:

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/reload-plugins
```

## gox-code-rules

| Skill | Invoke | Activates when | Content |
|---|---|---|---|
| Engineering | `/gox-code-rules:engineering` | session nudge + description (no file filter) | Karpathy guidelines: think first, keep it simple, surgical changes, goal-driven |
| Go | `/gox-code-rules:go` | Go tasks — nudge + description, model-invoked (`paths` declared, not load-bearing) | Go architecture + gin HTTP / cobra / gox-config / goose / time & timezone / scaffolding; detail in `references/`, read on demand |
| Frontend | `/gox-code-rules:frontend` | frontend tasks (same mechanism) | React / Vue / TS / JS / styling (skeleton; body TODO) |
| Shell | `/gox-code-rules:shell` | shell tasks (same mechanism) | bash/CLI scripts: stdout/stderr split, status prefixes, standard flags, exit codes, `test.sh` |

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

## Development

- Deps and tests: `make deps` (jq + bats-core), `make validate` (jq-check every manifest and the template), `make test` (all bats).
- Test layout: central `tests/` holds cross-plugin checks (`manifests` / `skills` / `template`, looping `plugins/*`, so new plugins are covered automatically); plugin-specific tests live under `plugins/<name>/tests/`. `make test` runs `bats tests plugins/*/tests`.
- Trigger/hit rate (does the model load a skill, does it delegate) is not a bats gate; it is probabilistic. Evaluate with the skill-creator eval flow (with-plugin vs baseline). `make eval` has the pointer.
- Adding a language or domain: one skill per language in the same plugin, each with `description` + `paths` + `references/`. See `docs/DESIGN.md`.

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
