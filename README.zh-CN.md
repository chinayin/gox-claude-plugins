# gox-claude-plugins

面向 Claude Code、Codex、Pi 和 Cursor 的团队技能与操作闸门。各平台使用自己的安装入口，规范正文和扫描逻辑集中维护；加载插件不往你的项目写入内容。

[English](README.md)

## 插件

| 插件 | 用途 |
|---|---|
| `gox-code-rules` | 团队代码规范，做成 Agent Skills（Go / 前端 / Shell / 技能编写 / 工程通则）。描述和会话提醒引导模型加载相关技能与细则，不保证自动触发。 |
| `token-thrift` | 把 token 密集的活交给 subagent：Claude 用 Haiku/Sonnet，Cursor 用 Composer/Grok，主会话负责决策。原文不进主上下文。 |
| `gox-guard` | 为支持的 agent 工具调用提供确定性闸门，扫描逻辑共享、入口按平台适配，不往 repo 写东西。首个闸门 `secrets`：`git push` 之前用 [betterleaks](https://github.com/betterleaks/betterleaks) 扫"本地有、任何远端都没有"的那段提交，有发现就拦下这次 push。 |
| `diagram-design` | 第三方（[cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design)，MIT），引用、不拷贝，跟随上游默认分支。40 种编辑风格的图出成单文件 HTML/SVG，附导入/导出命令。按需启用，不在默认模板里。登记与准入清单见 [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md)。 |

集中到一个 marketplace，避免把规范抄进每个 repo `CLAUDE.md` 的老问题：多 repo 漂移、占用 context、归属不清。技能是会话内软引导，可能不触发；真正的强制以 `golangci-lint` / CI / PR review 为准。`gox-guard` 是其中唯一确定性的一块：它执行外部扫描器、可以阻断一次工具调用，所以在下面单独说明。

## 四个平台如何区分

| 平台 | 安装入口 | 规范 / guard | token-thrift |
|---|---|---|---|
| Claude Code | `.claude-plugin/marketplace.json` → 各插件 `.claude-plugin/plugin.json` | `hooks/hooks.json`，匹配 `Bash` | `agents/`，Haiku/Sonnet |
| Codex | 复用 Claude 格式 marketplace 和插件清单 | 同一份 hooks，需在 Codex 单独信任 | 未适配 |
| Pi | 根 `package.json` → `.pi/extensions/` 与共享 skills | `tool_call` 的 `bash` → 共享 guard 脚本 | 未适配 |
| Cursor | `.cursor-plugin/marketplace.json` → 各插件 `.cursor-plugin/plugin.json` | `hooks/hooks-cursor.json`，匹配 `Shell` | `agents-cursor/`，Composer/Grok |

每个平台都有入口，但不要求每个平台都复制一套文件。`templates/project-settings.json` **仅用于 Claude Code**；安装命令按各平台小节使用，Cursor CLI 也有自己的 `/plugin` 界面。`tests/` 是维护者运行的自动化测试，agent 不会把它当作技能或规则加载。

## 安装到 Claude Code

项目级（推荐，随 git 共享）：把 `templates/project-settings.json` 并入该 repo 的 `.claude/settings.json` 并提交。`enabledPlugins` 是插件 ID 到布尔值的对象。项目配置声明该 repo 的启用范围，每位协作者仍需安装并信任插件。完整配置见 [USAGE.md](USAGE.md)。

单机：

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/plugin install gox-guard@chinayin
/plugin install diagram-design@chinayin   # 可选，第三方
/reload-plugins
```

`gox-guard` 还需要本机装有扫描器：`brew install jq betterleaks`（还需 Bash、Git；其他系统用包管理器安装 jq，用 `go install github.com/betterleaks/betterleaks@latest` 安装扫描器）。插件不会替你安装；装好之前，Claude 发起的 push 会被拦下并给出安装提示。

## 在 Codex 中使用

已使用 Codex CLI 0.155.1 验证：`gox-code-rules` 和 `gox-guard` 可以直接通过本仓库现有的 Claude 格式 marketplace 和 plugin 清单安装，无需独立的 Codex 包或构建步骤：

```sh
codex plugin marketplace add chinayin/gox-claude-plugins
codex plugin add gox-code-rules@chinayin
codex plugin add gox-guard@chinayin
```

安装后，在 Codex 中打开 `/hooks`，审查并信任插件的 hooks，再开启新会话。Hooks 需要 Bash 和 jq；`gox-guard` 还需要 betterleaks（见下文）。安装插件不会自动信任 hooks。

Codex 将自己的 marketplace 和插件启用配置保存在 `~/.codex/config.toml`；在 Claude Code 中安装或启用插件，不会自动替 Codex 配置。规范插件提供同一份 skills 和 SessionStart/SubagentStart 提醒，guard 提供依赖检查和 push 前扫描。已验证安装和 hooks 发现，尚未端到端验证受信任会话中的执行效果，也不保证两种模型行为完全一致。

`token-thrift` 依赖 Claude 专用模型和子代理，尚未完成 Codex 适配。`diagram-design` 通过完整 Git URL 的安装已验证，运行功能尚未完整验证。已有验证范围与后续工作统一见 [Codex 兼容说明](docs/CODEX.md)。

参见官方[插件文档](https://developers.openai.com/plugins/build/plugins)和 [hooks 信任说明](https://learn.chatgpt.com/docs/hooks)。

## Pi

仓库根的 `package.json` 声明了 pi 包，包含 `gox-code-rules` 的技能与提醒扩展、`gox-guard` 的 push 前扫描扩展：

```sh
pi install git:github.com/chinayin/gox-claude-plugins
```

guard 需要 Bash、jq、Git 和 betterleaks。`token-thrift` 尚未适配 pi，`diagram-design` 不在本包内。兼容范围、已做的验证与已知限制见 [pi 兼容说明](docs/PI.md)。

使用 pi-subagents 时，前台子代理不加载已安装的扩展（不受 guard 约束、收不到提醒），需按 [pi 兼容说明](docs/PI.md#pi-subagents-子代理需手动配置) 配置 `subagents.defaultSubagentOnlyExtensions`。

## 在 Cursor 中使用

使用 Cursor 原生插件管理器。先安装 [Cursor CLI](https://cursor.com/docs/cli/installation) 并登录，然后添加本仓库的 marketplace：

```sh
cursor-agent plugin marketplace add https://github.com/chinayin/gox-claude-plugins.git
cursor-agent
```

不传 `--git-ref` 时使用仓库默认分支（本仓为 `main`），不会自动选择最新 tag；只有需要指定其他分支、tag 或 commit 时才加该参数。

进入 CLI 后输入 `/plugin`，打开 Marketplace，选择 `chinayin`，分别安装 `gox-code-rules`、`gox-guard`、`token-thrift`，按需要选择 user 或 project 范围。添加 marketplace 是登记插件来源，还需要在管理器中选装插件。如果本机 CLI 名为 `agent`，替换命令前缀即可。依据：[Cursor CLI 命令](https://cursor.com/docs/cli/reference/slash-commands)。

使用 IDE 时，从 **Customize** 中找到可见 marketplace 的插件并点击 **Install**。团队也可在 Dashboard → Plugins & MCPs → Team Marketplaces 导入本仓库，再由成员安装。本仓库尚未上架公共 Cursor Marketplace，需要先添加仓库来源或由团队分发。依据：[Cursor Plugins](https://cursor.com/docs/plugins)。

Hooks 需要 Bash、jq，guard 还需 Git、betterleaks（macOS 可用 `brew install jq betterleaks`）。原生安装、刷新命令、Linux 依赖及可选的本地开发方式见 [Cursor 安装说明](docs/CURSOR.md#安装)。clone / 复制文件仅用于本地开发调试。

技能从选择器选择 `go`、`shell`、`engineering`、`delegate`；子代理使用 `/cheap-reader`、`/careful-writer`。Cursor hooks 转换共享扫描器的裁定并启用 `failClosed`；`.claude/settings.json` 不配置 Cursor。

已核对 CLI `2026.11.05-86047df` 的命令入口；账户侧实际安装、模型路由和客户端 hook / 权限执行仍需[客户端验收](docs/CURSOR.md#验证边界)。

## gox-code-rules

| 技能 | Claude Code 调用名 | 何时激活 | 内容 |
|---|---|---|---|
| 工程通则 | `/gox-code-rules:engineering` | 描述匹配（无文件限定） | Karpathy 准则：先想后写、简单优先、外科手术式改动、目标驱动 |
| Go | `/gox-code-rules:go` | Go 任务，通过提醒与描述引导模型调用 | Go 架构 + gin HTTP / cobra / gox-config / goose / 时间与时区 / 脚手架；细则在 `references/` 按需读 |
| 前端 | `/gox-code-rules:frontend` | 前端任务，通过描述引导模型调用 | React / Vue / TS / JS / 样式（骨架，正文 TODO） |
| Shell | `/gox-code-rules:shell` | Shell 任务，通过提醒与描述引导模型调用 | bash/CLI 脚本：stdout/stderr 分流、状态前缀、标准 flag、退出码、`test.sh` |
| Skill | `/gox-code-rules:skill` | 编写技能时，通过提醒与描述引导模型调用 | 命名（对象-动作，不带版本后缀）、正文语言、不写环境事实；只补官方 skill-creator 没定的事，不复述 |

表中命令属于 Claude Code；Cursor 从已安装技能选择器选择，Codex / Pi 使用各自的技能发现机制。Claude 的使用与排障见 [USAGE.md](USAGE.md)。`paths` 仅作声明，不保证按文件自动加载。

## token-thrift

把大量读取和已授权写入交给子代理，原始材料留在子代理上下文。实际费用还取决于模型、套餐、启动开销与重试次数。

| 角色 | Claude Code | Cursor 默认配置 | 职责 |
|---|---|---|---|
| `cheap-reader` | `haiku` | `composer-2.5[fast=false]` | 只读搜索、分析，返回结论 |
| `careful-writer` | `sonnet` | `grok-4.7[fast=false]` | 完成已授权修改并验证 |
| 主代理 | 当前会话模型，可由用户选择 Opus | 当前会话模型 | 编排、决策 |

这里对齐的是角色，不保证模型能力相等。Composer / Grok 使用 Cursor 自有模型用量池，`fast=false` 显式选择标准速度档；并非声称一定比所有 Claude 型号便宜。模型与费用依据：[Composer](https://cursor.com/docs/models/cursor-composer-2-5)、[Grok](https://cursor.com/docs/models/grok-4-7)。

Claude 读取 `agents/`，用 `/token-thrift:delegate` 加载策略；Cursor 读取 `agents-cursor/`，从选择器选择 `delegate`，用 `/cheap-reader`、`/careful-writer` 点名代理。Cursor reader 声明 `readonly: true`，不写 scratchpad。共用的委派策略按宿主选用实际工具接口。Codex / Pi 尚未提供 token-thrift 路由。

本地开发副本的模型定制：修改 `token-thrift/agents-cursor/*.md` 中的 `model`，填入 Cursor 支持的具体 ID，然后 Reload。套餐或管理员限制可能导致模型回退，须在子任务卡片确认实际运行模型；重新复制安装会覆盖本地修改。依据：[Cursor 子代理配置](https://cursor.com/docs/subagents)。

经验起点是约 3k token 的一次性材料才委派；小任务、主会话后续仍需原文的任务留在当前会话。agent 与技能正文用英文，README 面向使用者。

## gox-guard

为支持的 agent 工具调用提供确定性闸门。`hooks/secrets.sh` 负责扫描与裁定，`lib/push-scope.sh` / `lib/literal-args.jq` 负责仓库和源提交解析，各平台入口转换事件与输出。文案前缀 `[gox-guard/<闸名>]`，`GOX_GUARD_SKIP=1` 整体跳过。什么算闸门：能用确定性规则判断、只作用于对外且难以撤回的动作、不往 repo 写东西。建议性的检查归 `gox-code-rules`；只有 CI 能判断的事留在 CI。

### 闸门：secrets

只在"密钥泄漏变得不可逆"的那一刻设闸：push。之前的编辑、暂存、提交一律不碰，日常编码不会变重。

| 事件 | 行为 |
|---|---|
| 会话开始 | 检查 `PATH` 上有没有 `betterleaks`。有：零输出。没有：一句话让模型提醒你安装。 |
| 支持的平台传来含 `git … push` 的 shell 工具调用 | 解析目标仓库与推送源引用，再扫描不在任何本地远端跟踪引用中的提交。覆盖显式分支/refspec、tag、`--all`、`--mirror` 和配置的 push 映射。没有待推送提交：不扫直接放行。干净：放行（Cursor 显式返回 `permission: allow`）。有发现：**拒绝**这次 push，给模型一行一条的发现列表（规则、文件:行、提交、fingerprint，最多 10 条）和两句裁定规则。 |
| 扫描器（或 `jq`）缺失、扫描器出错 | 拦下并说明原因，而不是静默放行。会静默放行的闸门等于没有。 |

拦截文案刻意压短，因为它会进主 agent 的上下文；也不附手册，模型本来就会 git。它告诉模型的只有：

1. 真密钥：从对应提交里删掉，并告诉你这个值已经进过本地历史、建议轮换。绝不把真密钥加进白名单。
2. 单行误报：在该行加 `# betterleaks:allow` 注释。
3. 已提交的误报：把 fingerprint 追加到 `.betterleaksignore`。成规律的误报（测试夹具、示例）：在 `.betterleaks.toml` 里加路径/正则白名单。两者都是普通的提交文件，会出现在 review 里。

几个值得知道的取舍：

- **push 与修改命令分开执行。** 独立 commit 不受拦截。先完成 `git add` / `git commit`，再单独调用 `git push`，扫描才能看到最终提交。支持字面量 `cd '<repo>' && git push` 前缀及重复 `git -C`；其他命令链、shell 展开、远端组、多冒号 revision 表达式和未支持的选项会被拒绝，并提示拆分或简化命令。hook 不执行传入的命令文本。
- **子模块。** 递归推送子模块会被拒绝，包括 Git 配置隐式启用的递归。先分别推送各子模块，再对父仓库执行 `git push --recurse-submodules=no`，确保每个仓库都独立接受扫描。
- **本地计算范围。** 显式源引用解析成提交 ID；`--all` 选本地分支，`--tags` 选 tag，`--mirror` 选全部引用。matching 推送保守扫描全部本地分支。仍排除所有本地远端跟踪引用已包含的提交，hook 不执行 fetch 或查询服务器。
- **不要求配置文件。** 没配置就用扫描器内置规则。插件不写配置。betterleaks 1.10 的 TOML 配置需显式选择，例如在 agent 进程环境中设置 `BETTERLEAKS_CONFIG=/绝对路径/.betterleaks.toml`；仅创建该文件不会启用它。`.betterleaksignore` 从扫描目录读取。
- **不 pin 版本。** 只扫待推送区间，新规则不会让老提交突然报红。brew 给什么版本用什么。
- **永远脱敏，绝不联网验证。** `--redact` 常开（发现会进模型上下文与 transcript）；扫描器的在线验证功能永不开启（它会把疑似密钥发往厂商 API）。
- **覆盖边界。** 只覆盖实际到达 Claude/Codex hooks、Pi 扩展或 Cursor hooks 的调用。终端手敲、未加载扩展的子代理、脚本间接执行和 CI 不在完整覆盖承诺内：仓库 CI 仍是最后一道硬闸。
- **逃生口。** 环境变量 `GOX_GUARD_SKIP=1` 跳过闸门。模型被告知只有你明确要求时才用。

## 开发

- 默认已有 `python3`。`make deps` 安装 jq、bats-core 和 PyYAML；`make validate` 校验 JSON manifest 与模板；`make test` 运行全部 bats，直接用 `python3` 解析 YAML frontmatter。PyYAML 仅供测试使用。
- 测试分层：中央 `tests/` 放跨插件检查（`manifests` / `skills` / `template`，循环 `plugins/*`，新插件自动覆盖）；插件专属测试放 `plugins/<name>/tests/`。`make test` 运行 `bats tests plugins/*/tests` 和 `node --test tests/pi/*.test.mjs`。`tests/manifests-cursor.bats` 检查清单接线，不是团队代码规范；自定义平台文件统一用 `-cursor` 后缀，官方清单文件名保持原样。
- 触发/命中率（模型是否加载技能、是否派活）不进 bats，是概率性的，用 skill-creator eval 流程评估（with-plugin vs baseline）。`make eval` 有提示。
- `gox-guard` 的确定性 hook 测试用 stub 扫描器覆盖四种情形（干净 / 有发现 / 缺失 / 出错）。要跑真二进制，把 `GOX_GUARD_BIN` 指向一个 `betterleaks`，再往 hook 的 stdin 喂一段 PreToolUse JSON。
- 加语言或领域：一语言一技能，同插件内并存，提供描述并按需增加 references；`paths` 是声明性元数据。见[当前架构](docs/DESIGN.md)。

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
