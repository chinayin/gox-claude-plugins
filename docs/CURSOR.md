# Cursor 插件适配：调研结论与实施准备

文档整理于 2026-11-03，清单与 hook 脚本于同日落地。本文汇总 Cursor 对插件格式的支持方式、与 Claude / Agent Plugins 的关系，以及本仓的 Cursor Plugins 约定。Customize 里的安装界面、Cursor 会话内的真实 `git push` 拦截，以及 `token-thrift` 的模型别名是否生效，尚未在 Cursor 里点过。

相关文档：[DESIGN](DESIGN.md)（当前 Claude 架构）、[CODEX](CODEX.md)、[PI](PI.md)。参考实现：`obra/superpowers`（Shape A：shell-hook + `.cursor-plugin`）。

官方文档：

- [Plugins](https://cursor.com/docs/plugins.md)
- [Plugins reference](https://cursor.com/docs/reference/plugins.md)
- [Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md)
- [Agent Plugins](https://agent-plugins.org)（开放标准）

---

## 结论（先读）

1. Cursor **不执行** Claude Code 的 `/plugin marketplace|install`；安装走 Cursor Marketplace / Team marketplace / Customize / `~/.cursor/plugins/local`。
2. Cursor 并行支持两种**可正式安装**的格式，按清单探测，**不是「基础 + 增强」叠层**：
   - **Agent Plugins**（开放标准）：根目录 `plugin.json` → 只打包 **skills + MCP**
   - **Cursor Plugins**：`.cursor-plugin/plugin.json` → skills + MCP，再加 **rules / agents / commands / hooks / variables**
3. 本仓插件依赖 **hooks**（`gox-code-rules`、`gox-guard`）和 **agents**（`token-thrift`），Agent Plugins **能力面不够**。正式路径应对齐 superpowers：做 **Cursor Plugins**（加 `.cursor-plugin/`），并保留现有 `.claude-plugin/` 给 Claude。
4. 今天若 Cursor Settings → Agents → **Include Third-Party Plugins, Skills, and Other Configs** 开启，可部分吃到 Claude 侧已装插件的 skills / hooks / agents；这是兼容层，**不是** Cursor 一等公民分发。

---

## 三种清单对照

| 格式 | 清单位置 | 主要消费者 | 本仓现状 |
|---|---|---|---|
| Claude Code plugin | `.claude-plugin/plugin.json` + 仓库 `.claude-plugin/marketplace.json` | Claude `/plugin`；Codex 复用 | **已有** |
| Agent Plugins | 根目录 `plugin.json`（`$schema: agent-plugins.org/...`） | Cursor 等宣称兼容的工具 | **无**；且 hooks/agents 不在标准内 |
| Cursor Plugins | `.cursor-plugin/plugin.json` + 多插件仓库的 `.cursor-plugin/marketplace.json` | Cursor Marketplace / local | **已有**；三个本地插件。`diagram-design` 不在此列 |

加 `.cursor-plugin` **不是**「在 Agent Plugins 之上进一步支持」，而是选用 Cursor 完整插件形态。单个插件目录面向 Cursor 时通常只选 Agent Plugins **或** Cursor Plugins 一种；再另加 `.claude-plugin` 是第三套、给 Claude 用的。

`superpowers` 参考布局：有 `.claude-plugin/` + `.cursor-plugin/`，**没有**根目录 Agent Plugins 的 `plugin.json`。

### 组件能力面

| 组件 | Agent Plugins | Cursor Plugins | 本仓谁需要 |
|---|---|---|---|
| Skills | ✓ | ✓ | `gox-code-rules`、`token-thrift`（+ 第三方 `diagram-design`） |
| MCP | ✓ | ✓ | 当前无 |
| Rules | ✗ | ✓ | 可选；规范正文仍在 skills，不必强行搬成 rules |
| Agents | ✗ | ✓ | `token-thrift` |
| Commands | ✗ | ✓ | `diagram-design`（第三方）；本仓核心插件暂无 |
| Hooks | ✗ | ✓ | `gox-code-rules`、`gox-guard` |
| Variables | ✗ | ✓ | 暂无 |

---

## Cursor 如何加载

安装入口对两种格式相同（Customize → Install，或 Team marketplace）。Cursor 根据清单判断格式：

```text
根目录 plugin.json（符合 Agent Plugins）
  → 仅启用 skills + MCP

.cursor-plugin/plugin.json
  → 按默认目录或清单字段发现 skills / rules / agents / commands / hooks / mcp
```

Cursor Plugin 默认发现路径（清单未改写时）：`skills/`、`rules/`、`agents/`、`commands/`、`hooks/hooks.json`、`mcp.json`。

MCP 路径变量：Cursor 扩展 `${CURSOR_PLUGIN_ROOT}`，也认 `${CLAUDE_PLUGIN_ROOT}`；**不**扩展 Agent Plugins 标准的 `${PLUGIN_ROOT}` / `${PLUGIN_DATA}`。

本地调试：`~/.cursor/plugins/local/<name>/`（需允许 Local Plugin Imports）。指向仓库外的 symlink 会被跳过；应用复制或把仓库放进 local 目录内。

---

## 与 Claude hooks / Third-Party Imports 的关系

### Cursor 原生 hooks（正式插件）

- 配置：`hooks/hooks.json`，或清单 `"hooks": "..."`（superpowers 用 `hooks/hooks-cursor.json` 指向 Cursor 专用文件）。
- 事件名：camelCase（`sessionStart`、`preToolUse`、`subagentStart` 等）。
- `sessionStart` 注入：stdout JSON 的 **`additional_context`**（snake_case）。环境变量常有 `CURSOR_PLUGIN_ROOT`。

### Claude 兼容（Third-Party Imports）

- 来源：`.claude/settings.json`、`.claude/settings.local.json`、`~/.claude/settings.json`（以及已启用的 Claude 插件侧行为，视 Cursor 版本而定）。
- 事件名映射：`SessionStart` → `sessionStart`，`PreToolUse` → `preToolUse` 等。
- 响应：文档写明同时支持 Claude 嵌套 `hookSpecificOutput.additionalContext` 与 Cursor 扁平格式。
- 限制：不是 Marketplace 安装；依赖用户开开关；与 Claude 安装状态耦合。

### superpowers 双格式输出（推荐照抄）

`hooks/session-start` 按环境分支：

| 条件 | 输出字段 |
|---|---|
| `CURSOR_PLUGIN_ROOT` 已设 | `{ "additional_context": "..." }` |
| 仅 `CLAUDE_PLUGIN_ROOT`（Claude） | `hookSpecificOutput.additionalContext` |
| 其他 | 依平台；勿对 Claude 同时打两套以免重复注入 |

本仓 `gox-code-rules/hooks/session-nudge.sh`、`gox-guard/hooks/secrets.sh` 在 `CURSOR_PLUGIN_ROOT` 已设置时打 Cursor 扁平 JSON，否则打 Claude 的 `hookSpecificOutput`。一次只打一种。拒绝仍写在 JSON 里，脚本退出码保持 0：Cursor 文档把退出码 0 定义为采用 JSON 输出，退出码 2 是另一条等价的拒绝路径；团队 hook 脚本约定非零退出会干扰会话，所以不走退出码 2。

---

## 本仓各插件：Cursor 目标形态

原则（对齐 [PI](PI.md) / [DESIGN](DESIGN.md)）：

- **一份 skills / 扫描脚本正文**；不为 Cursor 复制规范内容。
- Claude 继续用 `.claude-plugin/` + 现有 `hooks/hooks.json`。
- Cursor 增加 `.cursor-plugin/`；多插件仓库根增加 `.cursor-plugin/marketplace.json`（与 Claude 的 marketplace **并列**，不互相替代）。
- 不把手改用户 `~/.cursor/hooks.json` 当作分发手段（与 superpowers porting 规则一致：走安装物）。

| 插件 | Cursor 组件 | 实施要点 | 优先级 |
|---|---|---|---|
| `gox-code-rules` | skills + hooks | `.cursor-plugin/plugin.json`；`sessionStart` / `subagentStart`；nudge 脚本双格式输出；skills 目录共用 | P0 |
| `gox-guard` | hooks | 同上；`preToolUse` 映射 Bash→Shell 若 matcher 需调整；保持 fail-closed 与 `GOX_GUARD_SKIP` | P0 |
| `token-thrift` | skills + agents | 声明 `agents/`；验证 Cursor Task / 模型别名是否等同 Claude；不足则文档标明降级 | P1 |
| `diagram-design` | 第三方 | 不复制进 `plugins/`；上游若有 Cursor 清单则文档说明单独安装；本仓 marketplace 可选引用 | P2 |

### 目录增量（已落地）

```text
.cursor-plugin/
  marketplace.json                 # name/owner/plugins[]，source 指向 plugins/<name>
plugins/gox-code-rules/
  .cursor-plugin/plugin.json       # name, skills, hooks
  hooks/hooks-cursor.json          # 或统一 hooks.json 若两平台 schema 可共用
  hooks/session-nudge.sh           # 增加 CURSOR_PLUGIN_ROOT 分支
plugins/gox-guard/
  .cursor-plugin/plugin.json
  hooks/hooks-cursor.json
  hooks/*.sh                       # 双格式 permission / additional_context
plugins/token-thrift/
  .cursor-plugin/plugin.json       # skills + agents
```

`marketplace.json` 示例字段（以官方 reference 为准）：`name`、`owner`、`plugins[].name`、`plugins[].source`（如 `plugins/gox-code-rules`）。解析时找 `<source>/.cursor-plugin/plugin.json`。

---

## 与 Codex / pi 适配策略的差异

| 平台 | 策略 |
|---|---|
| Codex | 直接复用 Claude marketplace / 清单，不新增第二套清单（见 [CODEX](CODEX.md)） |
| pi | 根 `package.json` + `.pi/extensions/*`，skills/guard 脚本单向复用（见 [PI](PI.md)） |
| Cursor | **需要** Cursor 专用清单与 hook 配置；skills 正文仍共用；正式安装不依赖 `/plugin` |

---

## 验收标准

已由 bats 覆盖：

1. 仓库根有 `.cursor-plugin/marketplace.json`；三个本地插件各有 `.cursor-plugin/plugin.json`，版本与 Claude 清单一致。`diagram-design` 不在 Cursor marketplace。
2. `hooks-cursor.json` 使用 camelCase 事件；`gox-guard` 的 matcher 是 `Shell`。Claude 的 `hooks/hooks.json` 仍匹配 `Bash`。
3. `CURSOR_PLUGIN_ROOT` 下，提醒是 `additional_context`，拒绝是 `permission` / `user_message`；只有 `CLAUDE_PLUGIN_ROOT` 时仍是 Claude 形状。`subagent_type: cheap-reader` 同样跳过提醒。顶层 `command` 与 `tool_input.command` 都能触发 push 扫描。
4. `make validate` 覆盖 Cursor JSON；`make test` 含 `tests/cursor-manifests.bats`。

尚未在 Cursor 界面里做：

1. `~/.cursor/plugins/local` 或 Team marketplace 导入后，Customize 能看到 skills 和 token-thrift agents。
2. 新 Cursor Agent 会话里，提醒来自正式插件 hook。
3. 临时仓库里，Cursor 的 Shell `git push` 被伪造 secret 拦住。需要记下当次 Cursor 版本与插件版本。
4. `token-thrift` 的 `model` / `tools` 是否被 Cursor 当成 Claude 的模型别名和工具白名单。对不上就保持文档里的降级说明。

非目标（首轮不做除非必要）：

- 把规范从 skills 迁到 Cursor rules
- 实现 Agent Plugins 根 `plugin.json`（本仓无纯 skills+MCP 包需求前不必）
- 复刻 Claude `/plugin` CLI
- 提交 public Cursor Marketplace（可先 Team / local）

---

## 还没在 Cursor 里点过的检查

1. 确认本机允许 Local Plugin Imports。把仓库复制进 `~/.cursor/plugins/local/`（指向仓库外的 symlink 会被跳过），从 Customize 安装三个插件。
2. 新开 Agent 会话，确认 `gox-code-rules` 提醒来自插件 hook。
3. 临时仓库加伪造 secret，确认 Shell `git push` 被 `gox-guard` 拦住，并记下 Cursor 版本与插件版本。
4. 试着调用 `cheap-reader` / `careful-writer`。若模型档或工具白名单不生效，把降级写进 README，不要改成「与 Claude 等价」。

---

## 调研来源摘要

- Cursor 文档对 Agent Plugins vs Cursor Plugins 的定义与组件表（2026-11 查阅）。
- 本机已装：`superpowers@claude-plugins-official`（含 Cursor 适配）、`gox-*@chinayin`（仅 Claude 清单）；Cursor `~/.cursor/plugins/cache` 为独立生态。
- 实测会话曾同时出现 superpowers bootstrap 与 `[gox-code-rules]` nudge，说明 Third-Party / 兼容路径已部分工作；正式分发仍缺 `.cursor-plugin`。
