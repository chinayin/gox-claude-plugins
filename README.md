# gox-claude-plugins

Team skills and action guards for Claude Code, Codex, Pi, and Cursor. Each host has its own installation entry; shared skills and scanning logic live in this repository. Loading a plugin does not write into your project.

[中文说明](README.zh-CN.md)

## Plugins

| Plugin | Purpose |
|---|---|
| `gox-code-rules` | Team coding standards as Agent Skills (Go / frontend / shell / skill authoring / engineering). Descriptions and session reminders guide the model to load relevant skills and references; automatic activation is not guaranteed. |
| `token-thrift` | Subagents for token-heavy work: Claude uses Haiku/Sonnet; Cursor uses Composer/Grok. The main session handles decisions. Raw material stays out of the main context. |
| `gox-guard` | Shared deterministic gates for supported agent tool calls, with host-specific entry points and nothing written into your repo. First gate, `secrets`: before `git push`, the commits not yet on any remote are scanned with [betterleaks](https://github.com/betterleaks/betterleaks) and a finding blocks the push. |
| `diagram-design` | Third-party ([cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design), MIT), referenced rather than copied; tracks the upstream default branch. Editorial diagrams (40 types) as standalone HTML/SVG plus import/export commands. Opt-in; not in the default template. Registry and intake checklist: [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md). |

Centralising standards here avoids the usual cost of copying them into every repo's `CLAUDE.md`: drift across repos, context bloat, and unclear ownership. The skills are in-session guidance and may not always trigger; final enforcement is `golangci-lint` / CI / PR review. `gox-guard` is the one deterministic piece: it runs an external scanner and can block a tool call, so it is documented separately below.

## Platform entry points

| Host | Installation entry | Rules / guard | token-thrift |
|---|---|---|---|
| Claude Code | `.claude-plugin/marketplace.json` → each `.claude-plugin/plugin.json` | `hooks/hooks.json`, `Bash` | `agents/`, Haiku/Sonnet |
| Codex | Reuses the Claude-format marketplace and manifests | Same hooks; explicitly trust them in Codex | Not adapted |
| Pi | Root `package.json` → `.pi/extensions/` and shared skills | `tool_call` for `bash` → shared guard script | Not adapted |
| Cursor | `.cursor-plugin/marketplace.json` → each `.cursor-plugin/plugin.json`; or local plugin copies | `hooks/hooks-cursor.json`, `Shell` | `agents-cursor/`, Composer/Grok |

Each host has an entry point, but not necessarily a separate copy of every file.
`templates/project-settings.json` and the `/plugin` commands below are **Claude Code only**.
`tests/` contains maintainer checks; no host loads these tests as skills or rules.

## Install in Claude Code

Per project (recommended, shared via git). Merge `templates/project-settings.json` into the repo's `.claude/settings.json` and commit. `enabledPlugins` maps plugin IDs to booleans. Project settings declare enablement for that repo; each collaborator still needs to install and trust the plugins. Full config in [USAGE.md](USAGE.md).

Single machine:

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/plugin install gox-guard@chinayin
/plugin install diagram-design@chinayin   # optional, third-party
/reload-plugins
```

`gox-guard` additionally needs the scanner on the machine: `brew install jq betterleaks` (Bash and Git are also required; on other systems install jq with your package manager and betterleaks with `go install github.com/betterleaks/betterleaks@latest`). The plugin never installs it for you; until it is present, pushes from Claude are blocked with an install hint.

## Use with Codex

Codex CLI 0.155.1 was verified to install `gox-code-rules` and `gox-guard` directly
from this repository's existing Claude-format marketplace and plugin manifests.
No separate Codex package or build step is needed:

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
codex plugin add gox-code-rules@chinayin
codex plugin add gox-guard@chinayin
```

In Codex, open `/hooks` to review and trust the plugins' hooks, then start a new
session. The hooks need Bash and jq; `gox-guard` also needs betterleaks (see below).
Installing a plugin does not automatically trust its hooks.

Codex stores its own marketplace and plugin enablement settings in
`~/.codex/config.toml`; installing or enabling these plugins in Claude Code does
not configure them in Codex. The rules plugin exposes the same skills and
SessionStart/SubagentStart reminders, and the guard exposes its dependency check
and pre-push scan. Installation and hook discovery were verified; identical model
behavior and trusted-session execution have not been verified end to end.
`token-thrift` depends on Claude-specific models and agents and has not been adapted
for Codex. Installation of `diagram-design` through its full Git URL was verified;
its runtime features have not been fully tested. See [Codex compatibility](docs/CODEX.md)
for the recorded verification scope and remaining work.

See the official [plugin documentation](https://developers.openai.com/plugins/build/plugins)
and [hook trust instructions](https://learn.chatgpt.com/docs/hooks).

## Pi

The root `package.json` declares a pi package: the `gox-code-rules` skills and
reminder extension, and the `gox-guard` pre-push scan extension:

```sh
pi install git:github.com/chinayin/gox-claude-plugins
```

The guard needs Bash, jq, Git and betterleaks. `token-thrift` has not been adapted
for pi, and `diagram-design` is not part of this package. See [pi compatibility](docs/PI.md)
(Chinese) for scope, verification and known limits.

With pi-subagents, foreground subagents do not load installed extensions (no guard,
no reminder); configure `subagents.defaultSubagentOnlyExtensions` as described in
[pi compatibility](docs/PI.md#pi-subagents-子代理需手动配置).

## Use with Cursor

For a local installation on macOS/Linux, install Bash, Git, jq, and betterleaks
first (`brew install jq betterleaks` on macOS; see [Linux setup](docs/CURSOR.md#安装)).
Then clone `main` and copy **each complete plugin** into its own local directory:

```sh
git clone --branch main https://github.com/chinayin/gox-claude-plugins.git
cd gox-claude-plugins
for plugin in gox-code-rules gox-guard token-thrift; do
  target="$HOME/.cursor/plugins/local/$plugin"
  mkdir -p "$target"
  cp -R "plugins/$plugin/." "$target/"
done
```

Each target must directly contain `.cursor-plugin/plugin.json`. The copy includes
hidden manifests, hooks, and `lib/`; copying only the scripts is insufficient.
Run **Developer: Reload Window** in Cursor, then check Customize for the three
plugins and their skills/agents. Local copies are discovered automatically when
allowed. Enterprise admins may need to enable **Allow Local Plugin Imports**;
this is an organization setting. See [Cursor's installation documentation](https://cursor.com/docs/plugins).

For Team marketplace installation, updates, and troubleshooting, see
[Cursor setup](docs/CURSOR.md#安装). This repository has not been submitted to the
public Cursor Marketplace. To upgrade, run `git pull --ff-only`
in the source checkout, repeat the copy, and reload; copying replaces local edits to these files.

Use the skill picker to select `go`, `shell`, `engineering`, or `delegate` from
the installed plugin; use `/cheap-reader` or `/careful-writer` for its custom
subagents. Claude's `/plugin` commands and `.claude/settings.json` do not configure
Cursor. The hook adapter supplies session guidance and enforces `allow` / `deny`
with `failClosed`; scanning and range selection use the shared guard library.

Automated tests cover manifests, protocol decisions, and installed-copy scanning.
Cursor UI discovery, actual model selection, readonly enforcement, and hook
execution inside the client still require [client acceptance](docs/CURSOR.md#验证边界).

## gox-code-rules

| Skill | Claude Code invocation | Activates when | Content |
|---|---|---|---|
| Engineering | `/gox-code-rules:engineering` | session nudge + description (no file filter) | Karpathy guidelines: think first, keep it simple, surgical changes, goal-driven |
| Go | `/gox-code-rules:go` | Go tasks — nudge + description, model-invoked (`paths` declared, not load-bearing) | Go architecture + gin HTTP / cobra / gox-config / goose / time & timezone / scaffolding; detail in `references/`, read on demand |
| Frontend | `/gox-code-rules:frontend` | frontend tasks, model-invoked from its description | React / Vue / TS / JS / styling (skeleton; body TODO) |
| Shell | `/gox-code-rules:shell` | shell tasks (same mechanism) | bash/CLI scripts: stdout/stderr split, status prefixes, standard flags, exit codes, `test.sh` |
| Skill | `/gox-code-rules:skill` | writing or editing a SKILL.md (same mechanism) | naming (`object-action`, no version suffix), body language, no environment facts; adds only what the official skill-creator leaves open |

The invocation column is for Claude Code. In Cursor, choose the installed skill from its picker; Codex and Pi use their own skill discovery. For Claude-specific examples and troubleshooting, see [USAGE.md](USAGE.md).

## token-thrift

Delegate large reads and authorized writes while keeping raw material out of the
parent's context. This can reduce repeated input, but total cost depends on the
models, plan, startup overhead, and retries.

| Role | Claude Code | Cursor default | Responsibility |
|---|---|---|---|
| `cheap-reader` | `haiku` | `composer-2.5[fast=false]` | Read-only searches and analysis; return findings |
| `careful-writer` | `sonnet` | `grok-4.7[fast=false]` | Make authorized changes and verify them |
| Main agent | Session model, including Opus if selected | Session model | Orchestration and decisions |

These are corresponding roles, not model-capability equivalents. Composer and
Grok use Cursor's own model pool; `fast=false` selects standard speed. This is not
a claim that they are always cheaper than every Claude model. See the official
[Composer](https://cursor.com/docs/models/cursor-composer-2-5) and
[Grok](https://cursor.com/docs/models/grok-4-7) model pages.

Claude uses `agents/` and `/token-thrift:delegate`; Cursor uses `agents-cursor/`,
its `delegate` skill picker entry, and `/cheap-reader` / `/careful-writer`.
Cursor's reader declares `readonly: true`; it never writes scratchpads.
The shared delegation policy does not assume the hosts have the same tool API.
Codex and Pi have no supported token-thrift routing yet.

For local Cursor model changes, edit the `model` field in the installed
`token-thrift/agents-cursor/*.md`, then reload. Choose a concrete available model
ID from Cursor, and check the task card for the model that actually ran; plan or
admin restrictions may cause fallback. Reinstallation can overwrite local edits.
See [Cursor subagent configuration](https://cursor.com/docs/subagents).

A starting heuristic is to delegate around 3k tokens of throwaway material;
keep small tasks or material the parent must reuse inline. Agent and skill
bodies are English; both READMEs are for people.

## gox-guard

Deterministic gates for supported agent tool calls. `hooks/secrets.sh` owns scan decisions, `lib/push-scope.sh` and `lib/literal-args.jq` resolve the repository and source commits, and host entry points adapt events and responses. Messages use the prefix `[gox-guard/<gate>]`; `GOX_GUARD_SKIP=1` skips the gate. What qualifies as a gate: a hard rule that can be decided deterministically, applied only to an outward, hard-to-undo action, writing nothing into the repo. Advisory checks belong in `gox-code-rules`; things only CI can decide stay in CI.

### Gate: secrets

Sits at the one moment a leaked credential becomes irreversible: the push. Everything before it (editing, staging, committing) stays untouched, so day-to-day coding is not slowed down.

| Event | What happens |
|---|---|
| Session start | Checks that `betterleaks` is on `PATH`. Present: silent. Missing: one line telling the model to ask you to install it. |
| A supported host sends a matching shell tool call containing `git … push` | Resolves the repository and push source refs, then scans commits not on any local remote-tracking ref. Explicit branches/refspecs, tags, `--all`, `--mirror`, and configured push mappings are covered. Nothing pending: allowed without scanning. Clean: allowed (Cursor receives explicit `permission: allow`). Findings: the push is **denied**; the model gets one line per finding (rule, file:line, commit, fingerprint; capped at 10) and a two-sentence verdict rule. |
| Scanner (or `jq`) missing, or scanner failing | The push is denied with the reason, not silently allowed. A gate that fails open is no gate. |

The block message is deliberately short because it lands in the main agent's context, and it carries no manual: the model already knows git. What it tells the model:

1. Real secret: remove it from the offending commits and tell you it already exists in local history and should be rotated. Never allowlist a real secret.
2. False positive on one line: `# betterleaks:allow` comment on that line.
3. False positive already committed: append the fingerprint to `.betterleaksignore`. Recurring pattern (fixtures, examples): a path/regex allowlist in `.betterleaks.toml`. Both are ordinary committed files that show up in review.

Design choices worth knowing:

- **Separate push from mutations.** Standalone commits are not gated. Run `git add` / `git commit` first, then invoke `git push` separately so the scan sees the final commits. A literal `cd '<repo>' && git push` prefix and repeated `git -C` are supported; other command chains, shell expansions, remote groups, multi-colon revision expressions, and unsupported options are denied with a request to split or simplify the command. No command text is evaluated by the hook.
- **Submodules.** Recursive submodule pushes are denied, including recursion enabled by Git configuration. Push each submodule separately, then push the parent with `--recurse-submodules=no` so each repository gets its own scan.
- **Local range calculation.** Explicit source refs are resolved to commit IDs. `--all` selects local branches, `--tags` selects tags, and `--mirror` selects all refs. Matching pushes conservatively scan all local branches. The exclusion still uses all local remote-tracking refs; the hook does not fetch or query a server.
- **No config required.** Without a config the scanner's built-in rules apply. The plugin never writes configuration. With betterleaks 1.10, a TOML config must be selected explicitly, for example by setting `BETTERLEAKS_CONFIG=/absolute/path/.betterleaks.toml` in the agent process environment; merely adding that file does not enable it. `.betterleaksignore` is read from the scan directory.
- **No version pinning.** Only the pending range is scanned, so a newer rule set can never turn old commits red. Use whatever `brew` gives you.
- **Always redacted, never validated.** `--redact` is always on (findings enter the model's context and transcript); the scanner's online validation feature is never enabled (it would send suspected secrets to vendor APIs).
- **Scope.** It only sees calls that reach the configured Claude/Codex hooks, Pi extension, or Cursor hooks. Manually typed terminal pushes, unhooked subagents, indirect script execution, and CI are outside complete coverage: the repo's CI remains the last hard gate.
- **Bypass.** `GOX_GUARD_SKIP=1` in the environment skips the gate. The model is told to use it only when you explicitly ask.

## Development

- Requires an existing `python3`. Run `make deps` to install jq, bats-core and PyYAML; `make validate` checks JSON manifests and the template; `make test` runs all bats, including YAML frontmatter parsing with `python3`. PyYAML is a test dependency only.
- Test layout: central `tests/` holds cross-plugin checks (`manifests` / `skills` / `template`, looping `plugins/*`, so new plugins are covered automatically); plugin-specific tests live under `plugins/<name>/tests/`. `make test` runs `bats tests plugins/*/tests` and `node --test tests/pi/*.test.mjs`. `tests/manifests-cursor.bats` checks Cursor manifest wiring, not the team coding rules; custom platform-specific filenames use a `-cursor` suffix. Official manifest names remain unchanged.
- Trigger/hit rate (does the model load a skill, does it delegate) is not a bats gate; it is probabilistic. Evaluate with the skill-creator eval flow (with-plugin vs baseline). `make eval` has the pointer.
- `gox-guard` has deterministic hook tests with a stub scanner (clean / findings / missing / failing). To exercise the real binary point `GOX_GUARD_BIN` at a `betterleaks` build and feed the hook a PreToolUse JSON on stdin.
- Adding a language or domain: one skill per language in the same plugin, with a description and references as needed. `paths` is declarative metadata, not an activation guarantee. See [current architecture](docs/DESIGN.md).

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
