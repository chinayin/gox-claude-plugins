# gox-claude-plugins

面向 Claude Code、Codex、Pi 和 Cursor 的团队代码规范、子代理与推送前密钥检查。

[English](README.md)

## 插件

| 插件 | 用途 |
|---|---|
| `gox-code-rules` | Go、Shell、技能编写及通用工程规范。 |
| `token-thrift` | 将大量阅读和可靠写入交给子代理，减少主会话上下文占用。支持 Claude Code、Cursor，以及可选择子代理模型的 Codex。 |
| `gox-guard` | 在受支持的 Agent 推送操作前扫描提交，发现密钥时阻止推送。 |
| `diagram-design` | 可选的第三方图表插件，见[详细说明](docs/THIRD_PARTY.md)。 |

## 运行依赖

Hooks 需要 Bash、jq；`gox-guard` 还需要 Git 和 [betterleaks](https://github.com/betterleaks/betterleaks)。macOS 安装：

```sh
brew install jq betterleaks
```

Linux 见[依赖安装说明](docs/CURSOR.md#运行依赖)。缺少依赖时，guard 会阻止推送。

## 安装到 Claude Code

在 Claude Code 会话中执行：

```text
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/plugin install gox-guard@chinayin
/plugin install diagram-design@chinayin   # 可选
/reload-plugins
```

项目配置与技能调用见[使用手册](USAGE.md)。

## 安装到 Codex

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
codex plugin add gox-code-rules@chinayin
codex plugin add gox-guard@chinayin
codex plugin add token-thrift@chinayin
```

在 `/hooks` 中审查并信任 hooks，再开启新会话。`token-thrift` 使用可用的低价子代理模型；无法选择时由主会话处理。详见 [Codex 说明](docs/CODEX.md)。

## 安装到 Pi

```sh
pi install git:github.com/chinayin/gox-claude-plugins
```

包含 `gox-code-rules` 和 `gox-guard`。使用 pi-subagents 时，前台子代理需要[额外配置](docs/PI.md#pi-subagents-子代理需手动配置)才能加载 guard 和规范提醒。

## 安装到 Cursor

安装并登录 [Cursor CLI](https://cursor.com/docs/cli/installation) 后，添加 marketplace：

```sh
cursor-agent plugin marketplace add https://github.com/chinayin/gox-claude-plugins
```

在 `cursor-agent` 会话中手动选装：

1. 输入 `/plugin`，打开 **Marketplace → chinayin**。
2. 分别选择 `gox-code-rules`、`gox-guard`、`token-thrift`，点击 **Install**。
3. 为每个插件选择 user 或 project 范围。安装后即加载，无需额外启用。

仅添加 marketplace 不会安装插件。IDE 安装与排障见 [Cursor 说明](docs/CURSOR.md#安装)。

## 文档

- [技能使用与排障](USAGE.md)
- 平台兼容说明：[Codex](docs/CODEX.md)、[Pi](docs/PI.md)、[Cursor](docs/CURSOR.md)
- [设计架构、guard 配置与开发](docs/DESIGN.md)
- [第三方插件](docs/THIRD_PARTY.md)与[更新记录](CHANGELOG.md)

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
