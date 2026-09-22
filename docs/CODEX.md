# Codex support

Codex CLI 0.155.1 can use the existing Claude marketplace and plugin manifests:

```text
.claude-plugin/marketplace.json       # shared marketplace: chinayin
plugins/gox-code-rules/               # same layout for gox-guard
├── .claude-plugin/plugin.json        # read by both clients
├── hooks/
└── skills/
```

No separate Codex manifest, marketplace, build step, or copied plugin is needed for
these two plugins. The marketplace name is `chinayin` in both clients.

## Install from GitHub

Requires a Codex version with Claude-compatible plugin and hook support; verified
with CLI 0.155.1. Hook dependencies are Bash and jq, plus betterleaks for gox-guard.

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
codex plugin add gox-code-rules@chinayin
codex plugin add gox-guard@chinayin
```

The GitHub commands use the default branch. The Codex-specific rules reminder in
this change becomes available there after merge. Before merge, reviewers can select
the PR branch with `--ref feat/codex-shared-plugins` on the marketplace-add command.

Review and trust the plugin hooks using `/hooks`, then start a new session. Installing
a plugin does not automatically trust its hooks.

For local development only, replace the marketplace-add command with
`codex plugin marketplace add "$PWD"` from the checkout root. Use one source for
`chinayin`; do not register both a checkout and GitHub under the same name.

## Compatibility

- `gox-code-rules`: all five shared skills. Frontend remains an unfinished placeholder,
  as in Claude; the reminder recommends Go, shell, skill authoring, and engineering.
- `gox-guard`: shared SessionStart dependency check and PreToolUse git-push check.
  Codex maps `exec_command` to `Bash` and provides `.tool_input.command`, matching the
  existing script. Indirect commands and subsequent `write_stdin` input are not a
  complete enforcement boundary.
- The shared marketplace also lists `token-thrift` and `diagram-design`. Listing or
  successful installation does not establish behavioral compatibility. `token-thrift`
  still depends on Claude agents/models; `diagram-design` has not been evaluated for
  Codex here. Only the two plugins above are covered by these instructions.

Codex discovers the existing `hooks/hooks.json` and supplies `CLAUDE_PLUGIN_ROOT`
for compatibility. The rules reminder checks Codex's documented `PLUGIN_ROOT`
extension to point to installed skill files rather than a Claude Skill tool. Its
Claude output remains unchanged. See the [official hook contract](https://learn.chatgpt.com/docs/hooks).

[Superpowers](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71)
uses shared skills with separate platform manifests, but its Codex manifest explicitly
sets `"hooks": {}`. Its hook script detects other hosts using environment variables;
it does not use our Codex `PLUGIN_ROOT` branch. We borrow its shared-content approach,
not its Codex hook behavior. A separate `.codex-plugin/plugin.json` would be useful
if we later need a Codex-specific override or presentation metadata, but is unnecessary
for the current plugins. Claude reads `.claude-plugin/plugin.json`; a Codex manifest
would not register a second Claude plugin or a second set of hooks.

The [OpenAI packaging documentation](https://developers.openai.com/plugins/build/plugins)
documents the legacy-compatible Claude marketplace and Claude-compatible manifests.
Portal conversion of an uploaded Claude archive is a separate distribution workflow.

## Verification

`make validate` and `make test` check manifests and script behavior. Codex app-server
`plugin/read` discovers 5 skills and 2 hook events for gox-code-rules, and 2 hook events
for gox-guard, using only the Claude manifests. GitHub default-branch installation was
also tested with an isolated temporary `CODEX_HOME`, using the commands above.
This does not verify hook execution in a trusted, installed model session.
