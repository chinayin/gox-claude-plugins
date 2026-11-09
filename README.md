# gox-claude-plugins

Team coding skills, subagents, and pre-push secret checks for Claude Code, Codex, Pi, and Cursor.

[中文说明](README.zh-CN.md)

## Plugins

| Plugin | Purpose |
|---|---|
| `gox-code-rules` | Go, Shell, skill authoring, and general engineering standards. |
| `token-thrift` | Delegate large reads and reliable writes to subagents, keeping the main context lean. Supports Claude Code, Cursor, and Codex with selectable subagent models. |
| `gox-guard` | Scan commits before supported agent push operations and block pushes that contain secrets. |
| `diagram-design` | Optional third-party diagram plugin. See [details](docs/THIRD_PARTY.md). |

## Prerequisites

Hooks need Bash and jq; `gox-guard` also needs Git and [betterleaks](https://github.com/betterleaks/betterleaks).
On macOS:

```sh
brew install jq betterleaks
```

For Linux, see [dependency setup](docs/CURSOR.md#运行依赖). Missing dependencies block guarded pushes.

## Install in Claude Code

In a Claude Code session:

```text
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/plugin install gox-guard@chinayin
/plugin install diagram-design@chinayin   # optional
/reload-plugins
```

For project configuration and skill commands, see the [usage guide](USAGE.md).

## Install in Codex

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
codex plugin add gox-code-rules@chinayin
codex plugin add gox-guard@chinayin
codex plugin add token-thrift@chinayin
```

Open `/hooks` to review and trust the hooks, then start a new session.
`token-thrift` uses available cheaper subagent models; otherwise it keeps work in the main session. See [Codex setup](docs/CODEX.md).

## Install in Pi

```sh
pi install git:github.com/chinayin/gox-claude-plugins
```

Installs `gox-code-rules` and `gox-guard`. With pi-subagents, foreground subagents
need [additional configuration](docs/PI.md#pi-subagents-子代理需手动配置) to load the guard and reminders.

## Install in Cursor

With [Cursor CLI](https://cursor.com/docs/cli/installation) installed and signed in, add the marketplace:

```sh
cursor-agent plugin marketplace add https://github.com/chinayin/gox-claude-plugins
```

In the `cursor-agent` session:

1. Enter `/plugin` and open **Marketplace → chinayin**.
2. Select `gox-code-rules`, `gox-guard`, and `token-thrift` in turn, and choose **Install**.
3. Choose user or project scope for each plugin. Installation loads the plugin; no separate enable step is needed.

Adding the marketplace alone does not install its plugins. See [Cursor setup](docs/CURSOR.md#安装) for IDE installation and troubleshooting.

## Documentation

- [Skills and usage](USAGE.md)
- [Codex](docs/CODEX.md), [Pi](docs/PI.md), and [Cursor](docs/CURSOR.md) compatibility
- [Architecture, guard configuration, and development](docs/DESIGN.md)
- [Third-party plugins](docs/THIRD_PARTY.md) and [changelog](CHANGELOG.md)

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
