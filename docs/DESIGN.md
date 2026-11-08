# 当前架构与维护约定

本文描述仓库当前实现，更新于 2026-11-03（Cursor 清单见 [CURSOR](CURSOR.md)）。安装见 [README](../README.zh-CN.md)，Claude 使用细节见 [USAGE](../USAGE.md)，Codex 支持范围见 [CODEX](CODEX.md)，pi 见 [PI](PI.md)。历史实验见 [MVP_FINDINGS](MVP_FINDINGS.md)，版本变化见 [CHANGELOG](../CHANGELOG.md)。

## 分发与目录

仓库用一个 `chinayin` marketplace 分发插件。Claude Code 是主要使用平台；Codex 直接复用现有 marketplace、插件清单和内容，不维护独立构建包或第二套规范。Cursor 使用并列的 `.cursor-plugin/` 清单（见 [CURSOR](CURSOR.md)），skills 正文仍共用。`diagram-design` 只出现在 Claude marketplace。

```text
.claude-plugin/marketplace.json        # Claude / Codex：本地插件与第三方 Git 源
.cursor-plugin/marketplace.json        # Cursor：三个本地插件，不含 diagram-design
plugins/
  gox-code-rules/
    .claude-plugin/plugin.json
    .cursor-plugin/plugin.json
    skills/                           # engineering、go、frontend、shell、skill
    hooks/                            # Claude hooks.json + Cursor hooks-cursor.json
    tests/
  token-thrift/
    .claude-plugin/plugin.json
    .cursor-plugin/plugin.json        # skills + agents；模型别名未在 Cursor 验证
    skills/delegate/                  # 委派策略
    agents/                           # cheap-reader / careful-writer
    tests/
  gox-guard/
    .claude-plugin/plugin.json
    .cursor-plugin/plugin.json
    hooks/                            # Claude 匹配 Bash；Cursor 匹配 Shell
    tests/
templates/project-settings.json       # Claude 项目配置模板
tests/                               # 跨插件结构、技能和模板校验
docs/                                # 当前设计、兼容边界、第三方登记、历史实验
```

`diagram-design` 通过 Git URL 引用上游，不复制到 `plugins/`。它是可选插件，不进入默认项目模板；审计记录见 [THIRD_PARTY](THIRD_PARTY.md)。

## 组件职责

| 组件 | 当前行为 | 边界 |
|---|---|---|
| `gox-code-rules` | 五个技能入口；Go 细则按 `references/` 索引读取；会话和子代理收到轻量提醒 | 软引导，不能保证模型加载或遵守；frontend 仍是占位内容，未提供 Python 技能 |
| `token-thrift` | Claude 的读任务委派给 Haiku，可靠写任务委派给 Sonnet，主模型接收结论。Cursor 清单声明同一份 skills 与 agents | 依赖 Claude 的模型与代理接口；Cursor 声明 `cheap-reader.readonly`，模型别名与运行时权限未验证；尚未完成 Codex 适配；成本收益需实测 |
| `gox-guard` | 对匹配的工具调用执行外部扫描器，并通过 hook 输出拒绝 push | 仅覆盖受支持且实际触发 hook 的调用；不能替代仓库 CI |

规范正文维护在各技能的 `SKILL.md` 和 `references/` 中，不复制进用户仓库。hooks 只提供提醒或执行检查，不向用户仓库写配置。用户仍需主动安装插件、配置启用范围；任务产生的代码或图表由对应任务决定。

## 技能加载与提醒

技能的 `description` 提供发现线索，`SKILL.md` 给出规则和索引，模型按当前任务读取 references。用户也可以在 Claude 中显式调用 `/gox-code-rules:go` 等技能。

`paths` 在本仓保留为声明性元数据，不承担自动加载保证。历史 Claude 实验中，实际加载通过模型调用 Skill 工具发生；没有观察到 `paths` 自动注入。实验结果只适用于当时客户端、模型和样本，不能外推为当前触发率。

`session-nudge.sh` 注册两个事件：

- `SessionStart`：提示模型按任务选择技能、避免重复加载；派写入子代理时把适用规范放进任务说明。
- Claude 的 `SubagentStart`：使用更短的提醒，优先遵循已有任务说明；对 `cheap-reader` 跳过注入。Cursor 不注册 `subagentStart`，由主代理通过任务 brief 传递规范。

提醒脚本 fail-open：缺少 jq、事件未知等情况下静默退出，不阻断会话。提醒中仍有 Claude Skill 工具相关措辞，Codex 下的实际加载效果需另行验证，见 [CODEX](CODEX.md)。

`session-nudge.sh` 固定输出 Claude 协议；Cursor 的 `cursor-session-nudge.sh` 仅处理 `SessionStart`，复用原文并转换为 `additional_context`。入口决定输出协议，不依赖插件根目录环境变量。

技能只提供软引导。格式化、lint、CI 和代码审查负责各自覆盖的检查；检查通过也不代表已经遵守全部团队规范。

## secrets 闸门

`gox-guard/hooks/secrets.sh` 在 `SessionStart` 检查 jq、betterleaks；在 `PreToolUse` 的 Bash 调用中匹配 `git … push`，扫描待推送提交。

- `lib/literal-args.jq` 只分词字面量参数；`lib/push-scope.sh` 解析 `cd '<repo>' &&`、重复 `-C`、显式源引用和默认 push 配置。源引用解析成提交 ID；`--all`、`--tags`、`--mirror` 分别选分支、tag、全部引用。matching 保守选全部本地分支。最终统一追加 `--not --remotes`，仍按本地远端跟踪引用排除已推送提交，不执行 fetch。
- 组合修改命令、多行命令、shell 展开、远端组、多冒号 revision 表达式、未知选项及无法解析的仓库/引用均拒绝，并提示把 push 拆开执行；不通过 eval 或 shell 执行用户命令。删除引用不发送新提交，单纯删除直接放行。递归子模块 push（包括配置隐式启用）也拒绝：先逐个推送子模块，再以 `--recurse-submodules=no` 推送父仓库。
- 没有待扫描提交时不调用扫描器；有发现、扫描器缺失或执行失败时拒绝这次 push。`secrets.sh` 固定输出 Claude 的 `permissionDecision: deny`；`cursor-secrets.sh` 将其转换为 `permission: deny`，原因同时传给用户和模型。阻断通过 JSON 表达，脚本退出码保持 0。
- Cursor 包装兼容顶层 `command` 与原生 `tool_input.command`，将 Shell 的 `working_directory` 归一为 `cwd`，相对路径以输入 `cwd` 为基准。缺 jq 时原始输入仍交给原脚本判断；需要拒绝但无法转换、子脚本非零退出或非空输出无效时，包装输出不依赖 jq 的固定拒绝。正常零输出在 `PreToolUse` 转换为显式 `permission: allow`。Cursor 配置启用 `failClosed: true`，进程启动失败、崩溃、超时或无输出由客户端拦截；空输入也拒绝。pi 继续直接调用 `secrets.sh`，保持其零输出放行约定。
- 始终启用 `--redact`，不启用扫描器的在线验证。扫描器不由插件安装。
- `GOX_GUARD_BIN` 可指定扫描器；`GOX_GUARD_SKIP=1` 跳过 push 检查，仅在用户明确要求时使用。

脚本依赖 Bash、jq、Git、betterleaks 和常规命令行工具，并使用临时文件接收扫描错误；不向用户仓库写入文件。人手在终端执行的 push、脚本间接调用等未被匹配的执行方式不在完整覆盖承诺内。Codex 的 hook 信任与运行验证边界见 [CODEX](CODEX.md)。

## 配置与升级

Claude 项目配置模板包含 `extraKnownMarketplaces` 和对象形式的 `enabledPlugins`，每个插件 ID 对应布尔值。模板默认启用三个本地插件；用户应将其合并到已有配置，而不是覆盖整个文件。

项目配置声明启用范围，不代替每位协作者安装插件。Codex 使用自己的安装与启用配置，不能直接套用 `.claude/settings.json`。具体操作统一维护在 README 和 USAGE，避免设计文档再复制一份安装示例。

插件版本由各自 `plugin.json` 管理，变更记录写入 CHANGELOG。修改已安装插件后，需要更新对应客户端的安装副本并重新加载或开启新会话；Codex hook 定义发生变化时还需重新审阅信任。仅修改源码或版本号不代表现有会话已更新。

## 验证与扩展

- `make validate` 检查 Claude 与 Cursor 的 marketplace、插件清单、Cursor hook 配置和模板的 JSON 语法，不是完整客户端 schema 或安装验证。
- `make test` 运行中央与各插件的 bats：技能 YAML、引用文件、模板格式与默认启用范围、提醒输出、扫描调用与阻断分支等。
- 技能触发、规范采纳、代理路由及费用用真实模型会话评估。`make eval` 提供评估提示，不执行模型测试。
- Codex 安装发现、受信任 hook 执行和模型行为属于不同验证层，不以其中一层通过代替其他层。

新增语言或领域时，在 `gox-code-rules/skills/` 下增加入口，按需增加 references，并同步说明与相关测试。若需要会话提醒指向新技能，还应检查提醒脚本。只有可确定判断、作用于对外操作的检查才考虑加入 `gox-guard`；每道闸门使用独立脚本与测试。

旧的按路径注入引擎、独立 Codex 打包及覆盖清单不属于当前架构。未采用方案保留在 Git / PR 历史中，不作为现行开发要求。
