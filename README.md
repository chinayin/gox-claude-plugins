# gox-claude-plugins

> Team coding standards for Claude Code — loaded on demand while you write code, with **zero writes to your repo**.

团队内部的 Claude Code 规范插件 marketplace（marketplace 名：`chinayin`）。把团队代码规范做成 **Agent Skills**：写代码时按需自动加载，对你的 repo **零写入**。

---

## 为什么用它

传统做法是把规范塞进每个 repo 的 `CLAUDE.md` 或文档里，问题很现实：

- **会漂移** —— 规范散落在 N 个 repo，改一处要同步 N 次，越改越不一致。
- **费 context** —— 规范越长，每次会话都被整段塞进上下文，挤占 token、稀释注意力。
- **难维护** —— 谁也说不清哪个 repo 的规范是最新的。

`gox-code-rules` 把规范集中到**一个 marketplace 仓库**，以技能形式分发：

- ✅ **零写入** —— 不往你的 repo 里塞任何规范正文，只在 `.claude/settings.json` 加几行启用配置。
- ✅ **按需渐进加载** —— 只在你**动相关文件**时才激活，且只读当前任务用得到的那一篇细则（cli / config / 迁移 / 脚手架），不整段灌。
- ✅ **集中维护、一处更新** —— 规范在本仓库统一维护，各 repo 通过插件自动拿到最新版，不再复制粘贴。
- ✅ **不阻断** —— 会话提示走 fail-open，出错也绝不打断你干活。

> 诚实说明：技能是会话内的**软引导**（模型按需加载，可能不触发）。**真正的强制以仓库的 `golangci-lint` / CI / PR review 为准。**

---

## 60 秒上手

### 团队 repo 启用（推荐，project-scope）

把 `templates/project-settings.json` 的内容并入该 repo 的 `.claude/settings.json` 并提交即可 —— 协作者信任该 repo 后，Claude Code 会提示启用本插件，**仅该 repo 生效**。完整配置见 [`USAGE.md`](USAGE.md)。

### 单机手动试用

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins
```

装好后，在含 `.go` 的项目里编辑 Go 文件，`go` 技能会自动激活；想强制加载随时输入 `/gox-code-rules:go`。

---

## 有哪些技能

| 技能 | 调用名 | 何时激活 | 内容 |
|---|---|---|---|
| 通用工程准则 | `/gox-code-rules:engineering` | 描述匹配即可（无文件限定） | Karpathy 准则：先想后写、简单优先、外科手术式改动、目标驱动 |
| Go 规范 | `/gox-code-rules:go` | 动 Go 文件（`**/*.go, go.mod...`）且任务相关 | Go 架构/编码 + cobra·gox/config·goose·脚手架，正文在 `references/` 按需读 |
| 前端规范 | `/gox-code-rules:frontend` | 动前端文件且任务相关 | React/Vue/TS/JS/样式（**骨架，正文 TODO 待填**） |
| Shell 规范 | `/gox-code-rules:shell` | 动 Shell 文件（`**/*.sh, **/*.bash`）且任务相关 | bash/CLI 脚本：stdout·stderr 分流、状态前缀、标准 flag、退出码、`test.sh`（单文件 SKILL.md） |

**怎么问能稳定触发、没触发怎么办** → 见 [`USAGE.md`](USAGE.md)。

---

## 开发

- 校验清单（JSON 等）：`brew install jq bats-core && bats tests/`
- 技能触发率：用 skill-creator 的 eval 流程评估 `go` 技能在真实 Go 任务下的自动激活率。
- 加新语言/领域：一语言一技能，同插件内并存，各带 `description` + `paths` + `references/`，详见 `docs/DESIGN.md`。

---

## License

[Apache License 2.0](LICENSE) © 2026 chinayin.
