# Cursor 安装、模型分档与共享边界

更新：2026-11-08。本文记录当前实现和自动化验证范围；Cursor 客户端验收尚未完成。总览见 [README](../README.zh-CN.md)，另见 [Codex](CODEX.md)、[Pi](PI.md)。

## 安装

CLI 支持项目配置声明和交互安装；IDE 使用插件管理器。本地目录加载放在后面的开发调试部分。

### Cursor CLI

安装 [Cursor CLI](https://cursor.com/docs/cli/installation) 并登录账号后，在终端添加本仓库的 marketplace：

```sh
cursor-agent plugin marketplace add https://github.com/chinayin/gox-claude-plugins
```

#### 项目级：从终端完成配置

仅添加 marketplace 不会安装其中的插件。接着在目标项目目录执行下面的命令，合并三个插件的启用声明：

```sh
(
  set -e
  mkdir -p .cursor
  [ -e .cursor/settings.json ] || printf '{}\n' > .cursor/settings.json
  cursor_settings_tmp="$(mktemp .cursor/settings.json.XXXXXX)"
  trap 'rm -f "$cursor_settings_tmp"' EXIT
  jq -e '
    .plugins["chinayin/gox-code-rules"].enabled = true |
    .plugins["chinayin/gox-guard"].enabled = true |
    .plugins["chinayin/token-thrift"].enabled = true
  ' .cursor/settings.json > "$cursor_settings_tmp"
  mv "$cursor_settings_tmp" .cursor/settings.json
)
```

需要 `jq`。命令保留其他配置和已有插件条目的额外字段；输入必须是有效 JSON。已有文件使用 JSONC 注释或尾逗号时，命令会停止并保留原文件，可手工把三个 `enabled: true` 条目合并进去。

插件键使用 `chinayin/<插件名>`。Cursor CLI 在该项目启动时读取 `.cursor/settings.json`，解析 marketplace 并加载声明的插件；写入配置不代表当前会话已经下载或加载完成。可提交该文件供协作者使用，协作者仍需能够访问 marketplace。此结构与交互安装选择 project 范围写入的一致，依据：[Cursor 团队答复](https://forum.cursor.com/t/feature-request-support-non-interactive-marketplace-plugin-installation-via-cursor-cli/176666)；本机 CLI 的项目配置写入和读取逻辑也已核对。

#### 账号级：CLI 内交互安装

1. 输入 `/plugin` 打开插件管理器。
2. 在 Marketplace → `chinayin` 选择 `gox-code-rules`、`gox-guard`、`token-thrift`。
3. 选择 user 范围完成账号级安装；也可以选择 project 写入上述项目配置。

交互安装后即重新加载，无需额外 enable。会话开始提醒使用 `sessionStart`，在下一次会话开始时触发。

添加来源也可以在交互会话内执行 `/plugin marketplace add https://github.com/chinayin/gox-claude-plugins`。如果 CLI 可执行文件名是 `agent`，替换终端示例的命令前缀即可。

CLI `2026.11.05-86047df` 没有独立的 `plugin install` / `plugin enable` 子命令，账号级安装目前没有无交互命令。项目级可使用上面的配置方式，不必进菜单。依据：[CLI slash 命令](https://cursor.com/docs/cli/reference/slash-commands)和前述项目配置说明。

#### 查看与刷新来源

查看来源或重新索引主分支：

```sh
cursor-agent plugin marketplace list
cursor-agent plugin marketplace update chinayin
```

重新索引后，项目声明的插件在新会话中重新解析；账号级安装可在 `/plugin` 管理器检查安装 / 更新状态。`marketplace update` 的职责是重新索引，不把它描述为已更新所有运行中的插件实例。

### Cursor IDE 与团队分发

已有可见 marketplace 时，在 **Customize** 中选插件、点击 **Install**，选择项目或用户范围。IDE 也提供 `/add-plugin` 安装入口。本仓库未上架公共 Cursor Marketplace，需先通过上面的 CLI 添加仓库来源，或由团队分发。[安装文档](https://cursor.com/docs/plugins)、[`/add-plugin` 发布说明](https://cursor.com/changelog/2-5)。

Teams / Enterprise 可在 Dashboard → Plugins & MCPs → Team Marketplaces 导入本仓库 URL，审查插件并设置访问范围。成员从 Customize 安装。来源使用主分支；管理员按需要设置自动刷新或手动 Refresh。该流程读取根 `.cursor-plugin/marketplace.json` 中的三个 `source`。[Team marketplaces](https://cursor.com/docs/plugins#team-marketplaces)。

### 运行依赖

安装插件后，运行 Cursor 的环境需能找到 Bash、jq；guard 还需要 Git、betterleaks。macOS 可执行 `brew install jq betterleaks`；Linux 用系统包管理器安装 Bash / Git / jq，再用 `go install github.com/betterleaks/betterleaks@latest` 或官方发布的二进制安装扫描器。扫描器不在 PATH 时，可在启动 Cursor 的环境中设置绝对路径 `GOX_GUARD_BIN`。插件不会代装扫描器。

### 本地开发调试（可选）

修改插件源码时才需要克隆仓库：

```sh
git clone --branch main https://github.com/chinayin/gox-claude-plugins
cd gox-claude-plugins
```

CLI 可用 `--plugin-dir` 在当前会话直接加载每个本地插件目录，无需复制：

```sh
cursor-agent --plugin-dir ./plugins/gox-code-rules --plugin-dir ./plugins/gox-guard --plugin-dir ./plugins/token-thrift
```

IDE 本地调试可按[官方本地测试流程](https://cursor.com/docs/plugins#test-plugins-locally)，复制完整插件后执行 **Developer: Reload Window**：

```sh
for plugin in gox-code-rules gox-guard token-thrift; do
  target="$HOME/.cursor/plugins/local/$plugin"
  mkdir -p "$target"
  cp -R "plugins/$plugin/." "$target/"
done
```

每个目录直接包含 `.cursor-plugin/plugin.json`；完整复制会保留 hooks 和 `lib/`。Enterprise 组织可能限制本地导入；同名 marketplace 安装优先于 IDE 本地副本。调试源码更新后重新加载；复制会覆盖本地修改。这不是正式安装或更新的必需步骤。

### 使用与排障

- 从技能选择器选择 `go`、`shell`、`engineering`、`delegate`；显式子代理使用 `/cheap-reader` 或 `/careful-writer`。
- 插件不可见时，先确认 marketplace 已添加 / 刷新、账号及组织访问范围正确，再检查是否已安装。只有本地开发副本才检查 `~/.cursor/plugins/local/`。
- guard 报缺依赖时，检查 Cursor 进程的 PATH；终端能运行扫描器不保证 GUI 启动的进程能找到它。
- `.claude/settings.json` 属于 Claude 配置。Cursor CLI 的 `/plugin` 是 Cursor 自己的管理器，不能因此推导其支持全部 Claude 子命令。

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

策略按经济阅读、可靠写入、主会话决策分档；具体模型由宿主配置选择。下面是当前 Cursor 默认值，不是自动追新别名。

| 任务档位 | Claude Code | Cursor 默认值 | 权限 |
|---|---|---|---|
| 大量阅读 / 搜索 | Haiku | `composer-2.5[fast=false]` | `cheap-reader`，`readonly: true` |
| 可靠写入 / 验证 | Sonnet | `grok-4.7[fast=false]` | `careful-writer`，允许写入，仍受任务授权约束 |
| 主会话决策 | 用户当前模型，可选 Opus | 用户当前模型 | 主会话权限 |

这是工作角色的对应关系，能力等价与成本收益尚未做基准测试。默认值考虑 Cursor 的模型用量池和任务复杂度；不是整个模型市场的最低价保证。`fast=false` 选择标准速度，`fast=true` 选择费用更高的 Fast 速度档；推理强度由独立的 `effort` 参数控制，关闭 Fast 不等于降低 effort。模型依据：[Composer](https://cursor.com/docs/models/cursor-composer-2-5)、[Grok](https://cursor.com/docs/models/grok-4-7)。

Claude 的 `haiku` / `sonnet` 是[官方模型别名](https://code.claude.com/docs/en/model-config#model-aliases)，随客户端和提供商映射更新，并不保证所有提供商同时用上最新版本。Cursor 自定义子代理目前公开支持具体模型 ID 或 `inherit`；未提供同等的 Grok / Composer 家族追新别名。升级默认模型需要更新 `agents-cursor/` 中的 `model` 字段；委派策略和代理职责不依赖版本号。

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

本轮核对了 Cursor CLI `2026.11.05-86047df` 的 `--version`、marketplace 帮助、交互 `/plugin` 实现及项目 `settings.json` 写入 / 读取逻辑；终端配置命令仅在临时项目中验证，未执行账户侧添加 / 安装，也未验证实际下载加载或 IDE 安装。待验证：

1. 记录 Cursor / 插件版本；按上面的安装步骤确认 Customize 中的组件。
2. 新开 Agent 会话确认规则提醒；子代理能启动并从 brief 获得规则。
3. 在临时仓库和本地 bare remote，用合成测试标记确认 Shell push 被拒绝、干净分支通过；模拟 hook 超时 / 启动失败确认 failClosed。
4. 检查两个代理实际运行的模型与费用；确认 reader 不能编辑文件或执行改变状态的命令。
