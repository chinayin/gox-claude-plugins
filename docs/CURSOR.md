# Cursor 安装、模型分档与共享边界

更新：2026-11-08。本文记录当前实现和自动化验证范围；Cursor 客户端验收尚未完成。总览见 [README](../README.zh-CN.md)，另见 [Codex](CODEX.md)、[Pi](PI.md)。

## 安装

### 本地安装（macOS / Linux）

1. 从主分支获取源码：

   ```sh
   git clone --branch main https://github.com/chinayin/gox-claude-plugins.git
   cd gox-claude-plugins
   ```

2. 确认运行 Cursor 的环境能找到 Bash、Git、jq、betterleaks。macOS 可执行 `brew install jq betterleaks`；Linux 用系统包管理器安装 Bash / Git / jq，再用 `go install github.com/betterleaks/betterleaks@latest` 或官方发布的二进制安装扫描器。扫描器不在 PATH 时，可在启动 Cursor 的环境中设置绝对路径 `GOX_GUARD_BIN`。

3. 在源码根目录复制三个**完整插件**，包括隐藏清单和 `lib/`：

   ```sh
   for plugin in gox-code-rules gox-guard token-thrift; do
     target="$HOME/.cursor/plugins/local/$plugin"
     mkdir -p "$target"
     cp -R "plugins/$plugin/." "$target/"
   done
   ```

   结果应为 `~/.cursor/plugins/local/gox-guard/.cursor-plugin/plugin.json` 等。`gox-guard/lib/push-scope.sh` 和 `literal-args.jq` 必须一并存在。

4. 在 Cursor 执行 **Developer: Reload Window**，再到 Customize 查看插件及其组件，开启新的 Agent 会话。

本地目录直接发现插件；Team marketplace 是另一种安装方式。本仓库未上架公共 Cursor Marketplace。Enterprise 管理员可在 Dashboard → Settings → Security & Identity → Marketplace and Plugins 管理 **Allow Local Plugin Imports**。外部符号链接可能被跳过；同名 marketplace 安装会优先于本地副本。依据：[Cursor Plugins](https://cursor.com/docs/plugins)。

升级时，在最初克隆的源码目录执行 `git pull --ff-only` 更新 main，再重复第 3 步复制和第 4 步 Reload。安装副本不是源码目录的实时链接；复制会覆盖本地模型修改，升级前先保存需要保留的定制。

### Team marketplace

Teams / Enterprise 在 Dashboard → Plugins & MCPs → Team Marketplaces 导入本仓库 URL，审查目录并发布访问范围，成员再从 Customize 安装相应插件。该流程读取根 `.cursor-plugin/marketplace.json` 中的三个 `source`。导入仓库主分支，后续更新按 Team marketplace 的刷新设置生效。具体管理选项见 [Team marketplaces](https://cursor.com/docs/plugins#team-marketplaces)。

### 使用与排障

- 从技能选择器选择插件的 `go`、`shell`、`engineering`、`delegate`；显式子代理使用 `/cheap-reader` 或 `/careful-writer`。Claude 的 `/plugin` 与 `.claude/settings.json` 不配置 Cursor。
- Customize 找不到组件时，先检查每个本地目录直属的 `.cursor-plugin/plugin.json`，再检查组织导入权限与同名 marketplace 副本，最后 Reload。
- guard 报缺依赖时，检查 **Cursor 进程**的 PATH；终端能运行扫描器不保证 GUI 启动的进程能找到它。
- 修改源码却仍运行旧逻辑时，重新复制完整插件并 Reload；不要只更新一个 hook，遗漏其相对路径依赖。

## 入口、命名与规范

| 平台 | 清单 / 包入口 | hook / 扩展 | token-thrift 代理 |
|---|---|---|---|
| Claude | 根及插件 `.claude-plugin/` | `hooks/hooks.json` → 共享脚本 | `agents/` |
| Codex | 复用 Claude 格式清单 | 同一份 `hooks.json`，另行信任 | 尚未适配 |
| Pi | 根 `package.json` | `.pi/extensions/` → 共享 guard | 尚未适配 |
| Cursor | 根及插件 `.cursor-plugin/` | `hooks/hooks-cursor.json` → `*-cursor.sh` → 共享脚本 | `agents-cursor/` |

文件命名以 [DESIGN 的命名约定](DESIGN.md#文件命名约定) 为准：闸门为 `hooks/<闸名>.sh`，平台包装为 `hooks/<职责>-<平台>.sh`，例如 `secrets-cursor.sh`。平台专用文件统一使用后缀，官方清单文件名不改。

`tests/manifests-cursor.bats` 是维护者执行的 Bats 合约测试，检查 marketplace → plugin → hook/agent 路径。它不提供给模型，也不定义 gox 代码规范。规范仍位于 `plugins/gox-code-rules/skills/*/SKILL.md` 和 `references/`。gox 技能命名规则适用于技能名，不要求所有测试文件都成为技能入口。

Cursor 使用原生插件清单来声明 hooks 和 agents；与 Claude 清单并存，复用技能正文。[官方插件格式说明](https://cursor.com/docs/reference/plugins)。

## push-scope 为什么拆到共享 lib

旧实现只按会话目录和 HEAD 扫描，不能覆盖在其他目录执行 `git -C ... push`、推送非当前分支等情况。`lib/push-scope.sh` 负责解析实际仓库和源引用，`lib/literal-args.jq` 只解析字面量参数。扫描器调用和拒绝文案仍只有 `hooks/secrets.sh` 一份；这项修复同时影响四个平台，不能仅验证 Cursor。

| 调用入口 | 归一化与输出 |
|---|---|
| Claude / Codex `hooks.json` | `Bash`、`PreToolUse` → `secrets.sh` → `hookSpecificOutput` |
| Pi `tool_call` | `bash` + `ctx.cwd` → `.pi/extensions/gox-guard.ts` → `secrets.sh`；deny 转成 `block: true` |
| Cursor `hooks-cursor.json` | `Shell`、`preToolUse` → `secrets-cursor.sh`；`working_directory` 归一为 `cwd`，deny 转成扁平 `permission` |

`Shell` / `Bash` 与 camelCase / PascalCase 是宿主协议差异，不能靠统一文件命名消除。Cursor 配置中传给包装脚本的 `PreToolUse` / `SessionStart` 是内部参数，用于调用共享脚本；事件注册键仍使用 Cursor 的 camelCase。

库通过脚本自身位置加载 `../lib/`，不依赖安装目录名称或用户工作目录。缺失 helper 或无法解析仓库 / 引用时拒绝；命令文本不被 eval。支持范围与保守拒绝的复杂命令见 [架构说明](DESIGN.md#secrets-闸门)。扫描范围仍排除所有本地远端跟踪引用，不查询实际服务器。

Cursor 的正常通过显式输出 `permission: allow`，失败输出 `deny`；`failClosed: true` 让客户端处理启动失败和超时。规则提醒仅注册 `sessionStart`，共享正文可指导没有 Skill 工具的宿主读取 SKILL.md；子代理通过任务 brief 收到规范，避免使用不支持上下文注入的 `subagentStart`。依据：[Cursor Hooks](https://cursor.com/docs/hooks)。

## token-thrift 模型分档

| 任务档位 | Claude Code | Cursor 默认值 | 权限 |
|---|---|---|---|
| 大量阅读 / 搜索 | Haiku | `composer-2.5[fast=false]` | `cheap-reader`，`readonly: true` |
| 可靠写入 / 验证 | Sonnet | `grok-4.7[fast=false]` | `careful-writer`，允许写入，仍受任务授权约束 |
| 主会话决策 | 用户当前模型，可选 Opus | 用户当前模型 | 主会话权限 |

这是工作角色的对应关系，能力等价与成本收益尚未做基准测试。默认值考虑 Cursor 的模型用量池和任务复杂度；不是整个模型市场的最低价保证。明确设置 `fast=false` 避免采用费用更高的 Fast 档。模型依据：[Composer](https://cursor.com/docs/models/cursor-composer-2-5)、[Grok](https://cursor.com/docs/models/grok-4-7)。

Cursor manifest 只指向 `agents-cursor/`，Claude 继续用 `agents/`。Cursor 代理不用 Claude 的 `haiku` / `sonnet` 别名或 `tools: Read, Bash, Skill` 白名单，也不假设存在 Claude 的 Skill 工具。只读代理不写 scratchpad，需要保存时由主代理处理。

本地定制可编辑 `~/.cursor/plugins/local/token-thrift/agents-cursor/*.md` 的 `model`，填入该 Cursor 版本可用的完整 ID，再 Reload。可选对应的 Claude Haiku / Sonnet 型号，或其他适合任务的模型；先确认套餐费用。`inherit` 会沿用主模型，失去独立定价档位。模型可能因组织或套餐限制回退，验收时看子任务卡片和用量记录；不能只看配置文件。依据：[Subagents](https://cursor.com/docs/subagents)。

## 验证边界

自动化检查：

- marketplace 与插件版本、引用路径、原生模型字段和只读字段；Claude 代理与 Cursor 代理分别校验。
- hooks 输入 / 输出、失败拒绝、缺 jq、继承其他宿主环境变量。
- 完整插件复制到带空格的临时安装目录，再从配置中的实际命令调用，验证 `../lib/` 加载。
- 真实 Git 提交图覆盖 `-C`、非 HEAD 分支、refspec、tag、mirror、配置 push 映射、删除、复杂命令拒绝；Pi 安装副本也验证非 HEAD / `-C` 和 helper 缺失。
- Pi 测试在 Node 24 / 26 下验证；恢复环境变量时保留 `process.env` 对象，避免 Node 26 子进程使用旧环境。

2026-11-08 另用真实 betterleaks 1.10.0 和显式合成规则，在临时安装副本中执行 Claude/Codex 共用配置命令、Cursor 配置命令，以及 Pi 1.5.0 原生扩展加载器加载的 handler：非 HEAD 测试分支被拒绝，干净待推送分支通过，返回消息不包含测试标记。仅使用本地 bare remote，没有真实凭据或外部推送，也未调用模型。

这些检查证明脚本和入口合约，不能证明四个客户端都已完整验收。Codex 既有安装发现记录见 [CODEX](CODEX.md)，Pi 历史主会话 / 子代理实测见 [PI](PI.md)，不能替代本次新范围解析的真实客户端验收。

Cursor 待验收项：本机尚未安装 Cursor，无法完成以下检查。

1. 记录 Cursor / 插件版本；按上面的安装步骤确认 Customize 中的组件。
2. 新开 Agent 会话确认规则提醒；子代理能启动并从 brief 获得规则。
3. 在临时仓库和本地 bare remote，用合成测试标记确认 Shell push 被拒绝、干净分支通过；模拟 hook 超时 / 启动失败确认 failClosed。
4. 检查两个代理实际运行的模型与费用；确认 reader 不能编辑文件或执行改变状态的命令。
