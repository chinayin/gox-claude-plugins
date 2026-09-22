# Codex support

Each supported plugin has two manifests and one shared implementation:

```text
.agents/plugins/marketplace.json      # Codex marketplace
.claude-plugin/marketplace.json       # Claude marketplace
plugins/gox-code-rules/               # same layout for gox-guard
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
├── hooks/
└── skills/
```

There is no build step or separate Codex copy. This follows the shared-directory
approach used by [superpowers](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71).
Unlike its `"hooks": {}` Codex manifest, these manifests retain default hook discovery.
Codex reads the existing `hooks/hooks.json` and supplies `CLAUDE_PLUGIN_ROOT` for
compatibility. The rules reminder uses Codex's `PLUGIN_ROOT` to point to the installed
skill files; its Claude output is unchanged.

## Install

Requires a Codex version with plugin and hook support; discovery was checked with
Codex CLI 0.155.1. Hook dependencies are Bash and jq, plus betterleaks for gox-guard.

From this checkout (including a review worktree):

```sh
codex plugin marketplace add "$PWD"
codex plugin add gox-code-rules@chinayin-codex
codex plugin add gox-guard@chinayin-codex
```

After this change is merged, the marketplace can instead be added from GitHub:

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
```

Review and trust the plugin hooks using `/hooks`, then start a new session. Installing
plugins does not automatically trust their hooks. Do not register both the checkout
and GitHub sources for the same marketplace.

## Scope and verification

- `gox-code-rules`: all five shared skills. Frontend remains an unfinished placeholder,
  as in Claude; the session reminder recommends Go, shell, skill authoring, and engineering.
- `gox-guard`: the shared SessionStart dependency check and PreToolUse git-push check.
  Codex maps `exec_command` to `Bash` and provides `.tool_input.command`, matching the
  existing script. Indirect commands and subsequent `write_stdin` input are not a
  complete enforcement boundary.
- `token-thrift` remains Claude-only because its delegation workflow specifies Claude
  agents and models. Third-party plugins are not republished into this marketplace.

`make validate` checks both platform manifests. `make test` covers marketplace paths,
platform versions, both reminder variants, and the shared guard behavior. Codex
app-server `plugin/read` was also used to check skill and hook discovery from this
checkout. These checks do not constitute an installed, trusted, end-to-end session test.

When releasing a shared plugin, keep the versions in its two manifests aligned.
See the [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks) for discovery,
trust, compatibility variables, and tool coverage.
