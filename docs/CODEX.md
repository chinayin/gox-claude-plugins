# Codex compatibility

Claude Code is the primary platform. Codex compatibility is a small configuration
patch; Claude manifests, skills, hook configurations, and scripts remain unchanged.

The shared marketplace is `chinayin`. Only `gox-code-rules` needs a Codex override:

```text
.claude-plugin/marketplace.json
plugins/gox-code-rules/
├── .claude-plugin/plugin.json        # primary Claude configuration
├── .codex-plugin/plugin.json         # Codex: shared skills, hooks disabled
├── hooks/                           # unchanged Claude reminders
└── skills/                          # shared content
```

The Codex manifest sets `"skills": "./skills/"` and `"hooks": {}`, following
[superpowers's Codex configuration](https://github.com/obra/superpowers/blob/5bf4e78011075bcfc0dc295f0724994cd123ee71/.codex-plugin/plugin.json).
Codex can discover and use the skills, but does not receive the Claude SessionStart
or SubagentStart reminders. No platform checks or Codex-specific prose are added to
the shared scripts. Keep the two rules-plugin manifest versions aligned when releasing.

`gox-guard` needs no Codex manifest: it reuses its Claude manifest and hooks directly.
Disabling its hooks would disable the guard itself.

## Install from GitHub

Verified with Codex CLI 0.155.1. Use a version with Claude-compatible plugin discovery
and manifest hook overrides. Guard dependencies are Bash, jq, and betterleaks.

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
codex plugin add gox-code-rules@chinayin
codex plugin add gox-guard@chinayin
```

These commands use the default branch; the rules-plugin Codex override is available
there after this PR merges. Before merge, reviewers can add the marketplace with
`--ref feat/codex-shared-plugins` to test this branch.

Review and trust the **gox-guard** hooks using `/hooks`, then start a new session.
Installing a plugin does not automatically trust its hooks. The rules plugin has no
Codex hooks to trust.

For local development only, replace the marketplace-add command with
`codex plugin marketplace add "$PWD"` from the checkout root. Use one source for
`chinayin`, either the checkout or GitHub.

## Scope and verification

- Rules: five shared skills; frontend remains its existing unfinished placeholder.
  Codex skill discovery does not guarantee that a model will consult every applicable rule.
- Guard: shared SessionStart dependency check and PreToolUse git-push check.
  Codex maps `exec_command` to `Bash`. Indirect commands and later `write_stdin`
  input remain outside a complete enforcement boundary.
- The shared marketplace also lists `token-thrift` and `diagram-design`. Token-thrift
  still depends on Claude agents/models; diagram-design has not been evaluated for
  Codex here. Only rules and guard are covered by these installation instructions.

`make validate` includes the Codex override. Codex app-server `plugin/read` verifies
5 skills and **zero hooks** for rules, and 2 hook events for guard. Real GitHub
installation with `@chinayin` was verified in a temporary isolated `CODEX_HOME`;
trusted hook execution in a model session has not been tested end-to-end.

See [Codex hook overrides and compatibility variables](https://learn.chatgpt.com/docs/hooks)
and [plugin packaging](https://developers.openai.com/plugins/build/plugins).
