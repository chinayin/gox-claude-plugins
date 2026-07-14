# gox-claude-plugins

Claude Code 团队插件，通过一个 marketplace（`chinayin`）分发。按需加载，不往你的 repo 写入任何内容。

[English](README.md)

## 插件

| 插件 | 用途 |
|---|---|
| `gox-code-rules` | 团队代码规范，做成 Agent Skills（Go / 前端 / Shell / 工程通则）。动相关文件时激活，只读当前任务用得到的那一篇细则。 |
| `token-thrift` | 把 token 密集的活外包给便宜模型的 subagent：读用 Haiku、写用 Sonnet、编排用 Opus。原文不进主上下文。 |

集中到一个 marketplace，避免把规范抄进每个 repo `CLAUDE.md` 的老问题：多 repo 漂移、占用 context、归属不清。技能是会话内软引导，可能不触发；真正的强制以 `golangci-lint` / CI / PR review 为准。

## 安装

项目级（推荐，随 git 共享）：把 `templates/project-settings.json` 并入该 repo 的 `.claude/settings.json` 并提交。协作者信任该 repo 后会被提示启用，作用域仅该 repo。完整配置见 [USAGE.md](USAGE.md)。

单机：

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/reload-plugins
```

## gox-code-rules

| 技能 | 调用名 | 何时激活 | 内容 |
|---|---|---|---|
| 工程通则 | `/gox-code-rules:engineering` | 描述匹配（无文件限定） | Karpathy 准则：先想后写、简单优先、外科手术式改动、目标驱动 |
| Go | `/gox-code-rules:go` | 动 Go 文件（`**/*.go, go.mod...`） | Go 架构 + cobra / gox-config / goose / 脚手架；细则在 `references/` 按需读 |
| 前端 | `/gox-code-rules:frontend` | 动前端文件 | React / Vue / TS / JS / 样式（骨架，正文 TODO） |
| Shell | `/gox-code-rules:shell` | 动 Shell 文件（`**/*.sh, **/*.bash`） | bash/CLI 脚本：stdout/stderr 分流、状态前缀、标准 flag、退出码、`test.sh` |

怎么问能稳定触发、没触发怎么办：见 [USAGE.md](USAGE.md)。

## token-thrift

把 token 密集的活外包给便宜模型的 subagent。主 agent（Opus）只做编排，大块原料不进它的上下文，后续每轮也就不再重发计费。

| 组件 | 调用名 | 模型 | 角色 |
|---|---|---|---|
| cheap-reader | `subagent_type: cheap-reader`（或 `@cheap-reader`） | Haiku | 只读：读飞书全文、大范围检索、查证、日志/长文分析，返回结论 |
| careful-writer | `subagent_type: careful-writer`（或 `@careful-writer`） | Sonnet | 正确性敏感的写入，如飞书 XML/block |
| delegate | `/token-thrift:delegate` | —— | 策略：何时外包、派哪档 |

装好后主 agent 会按各 agent 的 description 判断是否外包；也可显式点名，或用 `/token-thrift:delegate` 强制加载策略。

经验阈值：subagent 要处理的“用完即弃”原料约 3k token 以上就外包；任务很小、或原文后续还要复用，则内联。

agent 与技能正文用英文编写（对模型更友好）；本文件与英文 README 面向人。

## 开发

- 依赖与测试：`make deps`（jq + bats-core）、`make validate`（jq 校验所有 manifest 与模板）、`make test`（全部 bats）。
- 测试分层：中央 `tests/` 放跨插件检查（`manifests` / `skills` / `template`，循环 `plugins/*`，新插件自动覆盖）；插件专属测试放 `plugins/<name>/tests/`。`make test` = `bats tests plugins/*/tests`。
- 触发/命中率（模型是否加载技能、是否派活）不进 bats，是概率性的，用 skill-creator eval 流程评估（with-plugin vs baseline）。`make eval` 有提示。
- 加语言或领域：一语言一技能，同插件内并存，各带 `description` + `paths` + `references/`。见 `docs/DESIGN.md`。

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
