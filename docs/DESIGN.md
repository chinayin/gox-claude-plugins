# 当前架构与维护约定

本文描述仓库当前实现，更新于 2026-11-09（Cursor 清单见 [CURSOR](CURSOR.md)）。安装见 [README](../README_CN.md)，Claude 使用细节见 [USAGE](../USAGE.md)，Codex 支持范围见 [CODEX](CODEX.md)，pi 见 [PI](PI.md)。历史实验见 [MVP_FINDINGS](MVP_FINDINGS.md)，版本变化见 [CHANGELOG](../CHANGELOG.md)。

## 分发与目录

仓库用一个 `chinayin` marketplace 分发插件。Claude Code 是主要使用平台；Codex 直接复用现有 marketplace、插件清单和内容，不维护独立构建包或第二套规范。Cursor 使用并列的 `.cursor-plugin/` 清单（见 [CURSOR](CURSOR.md)），skills 正文仍共用。`diagram-design` 只出现在 Claude marketplace。

```text
.claude-plugin/marketplace.json        # Claude / Codex：本地插件与第三方 Git 源
.cursor-plugin/marketplace.json        # Cursor：三个本地插件，不含 diagram-design
plugins/
  gox-code-rules/
    .claude-plugin/plugin.json
    .cursor-plugin/plugin.json
    skills/                           # engineering、go、frontend、shell、bashly、scaffold、skill
    hooks/                            # Claude hooks.json + Cursor hooks-cursor.json
    tests/
  token-thrift/
    .claude-plugin/plugin.json
    .cursor-plugin/plugin.json        # skills + agents-cursor（原生模型与权限）
    skills/delegate/                  # 委派策略
    agents/                           # Claude：cheap-reader / careful-writer
    agents-cursor/                    # Cursor：同名角色，独立模型与权限
    tests/
  gox-guard/
    .claude-plugin/plugin.json
    .cursor-plugin/plugin.json
    hooks/                            # Claude 匹配 Bash；Cursor 匹配 Shell
    lib/                              # 共享仓库/源引用解析、默认扫描配置，不含平台协议
    skills/secret-triage/             # 拦截后的发现裁定流程
    tests/
templates/project-settings.json       # Claude 项目配置模板
package.json                         # Pi 包：扩展和共享技能入口
.pi/extensions/                      # Pi 事件和提示适配
tests/                               # 跨插件结构、技能和模板校验；pi/ 放扩展测试
docs/                                # 当前设计、兼容边界、第三方登记、历史实验
```

`diagram-design` 通过 Git URL 引用上游，不复制到 `plugins/`。它是可选插件，不进入默认项目模板；审计记录见 [THIRD_PARTY](THIRD_PARTY.md)。

## 文件命名约定

沿用 `gox-guard` 的既有约定：每道闸门一个 `hooks/<闸名>.sh`，如 `secrets.sh`；该规则不要求增加 `hook-` 前缀或 `-hook` 后缀。`hooks/` 目录已经标明脚本用途。规则提醒继续使用职责名 `session-nudge.sh`。

| 文件角色 | 命名与位置 | 本仓示例 |
|---|---|---|
| 共享 hook 脚本 | `hooks/<职责>.sh`；guard 的职责名即闸名 | `secrets.sh`、`session-nudge.sh` |
| 平台协议包装 | 在原职责名后加 `-<平台>` | `secrets-cursor.sh`、`session-nudge-cursor.sh` |
| hook 注册配置 | 保留 `hooks.json`；专用配置加平台后缀 | `hooks.json`、`hooks-cursor.json` |
| 共享辅助库 | `lib/<职责>.sh` 或对应语言扩展名 | `push-scope.sh`、`literal-args.jq` |
| 测试 | `tests/<职责>.bats`；平台专项加后缀 | `push-scope.bats`、`manifests-cursor.bats` |

辅助库由 hook 加载，不作为独立 hook 注册；平台包装只适配协议，不新增一份扫描规则。Pi 入口由 `.pi/extensions/` 目录区分。官方约定的 `.claude-plugin/plugin.json`、`.cursor-plugin/plugin.json`、`SKILL.md` 等文件名保持原样。gox 的 `object-action` 规则针对技能名，不能用它推导 hook 文件必须带某个前后缀。

## 组件职责

| 组件 | 当前行为 | 边界 |
|---|---|---|
| `gox-code-rules` | 七个技能入口；Go 与 scaffold 的细则按 `references/` 索引读取；会话和子代理收到轻量提醒 | 软引导，不能保证模型加载或遵守；frontend 仍是占位内容，未提供 Python 技能 |
| `token-thrift` | Claude 使用 Haiku / Sonnet，Cursor 使用 agents-cursor 中的 Composer / Grok 标准档；Codex 在共享 delegate 中按任务档位选择当前可用模型，通过原生子代理接口传递任务 | Codex 无合适低价模型时退回主线程；文字只读约束不等于沙箱隔离；实际费用需测量；Pi 尚未适配 |
| `gox-guard` | 对匹配的工具调用执行外部扫描器，并通过 hook 输出拒绝 push | 仅覆盖受支持且实际触发 hook 的调用；不能替代仓库 CI |

规范正文维护在各技能的 `SKILL.md` 和 `references/` 中，不复制进用户仓库。hooks 只提供提醒或执行检查，不向用户仓库写配置。用户仍需主动安装插件、配置启用范围；任务产生的代码或图表由对应任务决定。

### token-thrift 的上下文成本

目标是减少高价主模型处理低级任务的用量。`delegate` 只供主代理做调度；它在读取大段原文前传递源位置与简短任务说明，执行子代理只加载必要业务技能，不再加载或转发调度策略，也不继续委派，除非任务明确要求。关联输入尽量合并到一次委派；相似任务复用已确认的模型选择，任务要求或可用性变化时再判断。

共享技能保留执行所需规则；模型能力比较、计费解释与验证方法放在文档中。正文变短只证明文本开销降低，不证明实际调用更省。Codex 默认先暴露技能元数据，按需加载正文；新建上下文也仍有宿主指令、工具和技能列表开销，见[技能加载说明](https://learn.chatgpt.com/docs/build-skills)。不能假定每个子代理都会读全文，也不能假定它没有固定开销。

收益验收应在相同原始输入、预期结果和质量标准下比较直接处理与委派：分别记录主模型的输入、缓存输入及输出 token，子代理用量，以及工具调用和返工。主模型处理量是否下降是首要指标，总费用或订阅额度是否下降另行判断；相同模型的上下文隔离也不能算作低价模型路由。约 3,000 token 仅是经验起点。现有测试不提供完整的宿主用量数据，因此尚不能证明净节省比例。

## 技能加载与提醒

技能的 `description` 提供发现线索，`SKILL.md` 给出规则和索引，模型按当前任务读取 references。用户也可以在 Claude 中显式调用 `/gox-code-rules:go` 等技能。

`paths` 在本仓保留为声明性元数据，不承担自动加载保证。历史 Claude 实验中，实际加载通过模型调用 Skill 工具发生；没有观察到 `paths` 自动注入。实验结果只适用于当时客户端、模型和样本，不能外推为当前触发率。

`session-nudge.sh` 注册两个事件：

- `SessionStart`：提示模型按任务选择技能、避免重复加载；派写入子代理时把适用规范放进任务说明。
- Claude 的 `SubagentStart`：使用更短的提醒，优先遵循已有任务说明；对 `cheap-reader` 跳过注入。Cursor 不注册 `subagentStart`，由主代理通过任务 brief 传递规范。

提醒脚本 fail-open：缺少 jq、事件未知等情况下静默退出，不阻断会话。无 Skill 工具时提醒模型读取已安装的 SKILL.md 与相关 references；Codex 下实际加载效果仍需另行验证，见 [CODEX](CODEX.md)。

`session-nudge.sh` 固定输出 Claude 协议；Cursor 的 `session-nudge-cursor.sh` 仅处理 `SessionStart`，复用原文并转换为 `additional_context`。入口决定输出协议，不依赖插件根目录环境变量。

技能只提供软引导。格式化、lint、CI 和代码审查负责各自覆盖的检查；检查通过也不代表已经遵守全部团队规范。

## secrets 闸门

`gox-guard/hooks/secrets.sh` 在 `SessionStart` 检查 jq、betterleaks，依赖齐全时给模型一句"push 单独执行"的提示；在 `PreToolUse` 的 Bash 调用中匹配 `git … push`，扫描待推送提交。

- 直接 Git 调用支持裸 `git` 和末段为 `git` 的字面量路径，包括带空格的引用路径。预筛命中后，`literal-args.jq` 仅为完整的 `echo` / `cat` / `grep` / `rg` 字面量参数、`printf` 的普通文字与 `%s` / `%%` 输出，以及单个 `cat <<'DELIM'` 引用 heredoc 确认文本放行。`printf -v` / `%n`、`rg --pre` / `--hostname-bin` 等可能执行或求值的形式不在此范围。未知程序、组合命令和 shell 展开继续保守检查，不执行输入命令。
- `lib/literal-args.jq` 只分词字面量参数；`lib/push-scope.sh` 解析 `cd '<repo>' &&`、重复 `-C`、显式源引用和默认 push 配置。源引用解析成提交 ID；`--all`、`--tags`、`--mirror` 分别选分支、tag、全部引用。matching 保守选全部本地分支。最终统一追加 `--not --remotes`，仍按本地远端跟踪引用排除已推送提交，不执行 fetch。
- push 之后的输出重定向（`2>&1`、指向 `/dev/null`）和由 `;`、`&&`、`|` 引出的后续命令不改变推送内容，解析时只取开头的 push 一段；后续命令里再出现 `push` 则拒绝，避免有一次推送没被扫描。
- push 之前的组合命令、重定向到文件、后台执行、多行命令、shell 展开、远端组、多冒号 revision 表达式、未知选项及无法解析的仓库/引用均拒绝，并提示把 push 拆开执行；不通过 eval 或 shell 执行用户命令。删除引用不发送新提交，单纯删除直接放行。递归子模块 push（包括配置隐式启用）也拒绝：先逐个推送子模块，再以 `--recurse-submodules=no` 推送父仓库。
- 没有待扫描提交时不调用扫描器；有发现、扫描器缺失或执行失败时拒绝这次 push。`secrets.sh` 固定输出 Claude 的 `permissionDecision: deny`；`secrets-cursor.sh` 将其转换为 `permission: deny`，原因同时传给用户和模型。阻断通过 JSON 表达，脚本退出码保持 0。
- Cursor 包装兼容顶层 `command` 与原生 `tool_input.command`，将 Shell 的 `working_directory` 归一为 `cwd`，相对路径以输入 `cwd` 为基准。缺 jq 时原始输入仍交给原脚本判断；需要拒绝但无法转换、子脚本非零退出或非空输出无效时，包装输出不依赖 jq 的固定拒绝。正常零输出在 `PreToolUse` 转换为显式 `permission: allow`。Cursor 配置启用 `failClosed: true`，进程启动失败、崩溃、超时或无输出由客户端拦截；空输入也拒绝。pi 继续直接调用 `secrets.sh`，保持其零输出放行约定。
- 始终启用 `--redact`，不启用扫描器的在线验证。扫描器不由插件安装。
- `GOX_GUARD_BIN` 可指定扫描器；`GOX_GUARD_SKIP=1` 跳过 push 检查，仅在用户明确要求时使用。

脚本依赖 Bash、jq、Git、betterleaks 和常规命令行工具，并使用临时文件接收扫描错误；不向用户仓库写入文件。人手在终端执行的 push、脚本间接调用等未被匹配的执行方式不在完整覆盖承诺内。Codex 的 hook 信任与运行验证边界见 [CODEX](CODEX.md)。

### 扫描器配置与误报处理

betterleaks 1.10 起不再自动发现仓库内的 TOML，由调用方显式选择配置，闸门按以下顺序选择：

1. 环境变量 `BETTERLEAKS_CONFIG` / `BETTERLEAKS_CONFIG_TOML`（及 `GITLEAKS_*` 旧名）已设置时，闸门不干预，由扫描器读取。
2. 否则仓库根存在 `.betterleaks.toml` 时，以 `-c` 传给扫描器。文件取自工作树，与 `.betterleaksignore` 一致。
3. 否则以 `-c` 传入插件自带的 `gox-guard/lib/betterleaks.toml`：内置规则加一条 mock 约定。

配置之间是替换而非合并：仓库自带配置时，mock 约定须由该文件自己写上。既无 `[[rules]]` 也无 `[extend]` 的仓库配置会让扫描不检查任何内容，闸门直接拒绝。`.betterleaksignore` 从扫描目录读取，与配置叠加生效：发现被配置、行内注释或忽略文件任一排除即不上报。扫描器不在 PATH 时，可用 `GOX_GUARD_BIN` 指定绝对路径。

分工：`.betterleaks.toml` 是团队策略（自定义规则、额外的放行写法），改动由用户决定；`.betterleaksignore` 记录逐条核实过的例外。同一条发现只在一处处理。

mock 约定是固定的：假的密码、token、key 一律以 `mock-` 开头。它分两头落地，互不读取对方：写代码时由 `gox-code-rules` 的会话提醒给出这一句规则，不读扫描器配置；推送前由闸门的默认配置放行值以 `mock-` 开头的发现。规则直接写在提醒里而不做成技能：全文只有一句，做成技能反而多出描述的常驻开销、正文的加载开销和触发不确定性。`secret-triage` 只处理漏网的发现。

默认规则确实会拦这类值（1.10.1 实测：密码字段和带凭证的 URL 里的 `mock-password` 被 `generic-password`、`generic-credential-uri` 报出），所以闸门必须带这条放行；它只按值的开头判断，带 `mock-` 前缀的厂商格式 token 仍会上报，因为匹配从 token 本身开始。必须保留真实格式的值用行内 `betterleaks:allow`。放行写成顶层 `filter` 表达式，1.10.1 实测可用，也是 v2 保留的写法；`[[allowlists]]` 仅 1.x 支持。

betterleaks v2（2026-11-17 为 rc.9，尚未进入 Homebrew）改动了本闸门依赖的接口：报告参数与 JSON 结构、`.betterleaksignore` 改为密钥值的 SHA-256 且不再接受位置指纹。当前脚本只在 1.10.1 上验证，未适配 v2；v2 稳定版发布后闸门会因扫描器报错而拒绝 push，需先适配或用 `GOX_GUARD_BIN` 指向 v1。

拦截结果只返回脱敏后的规则、文件位置、提交与 fingerprint，最多十条；超出时附同一区间的只读重扫命令。裁定与处理步骤只维护在技能 `gox-guard/skills/secret-triage/SKILL.md`，拦截文案保留两句裁定规则并点名该技能；忽略文件与白名单的变更应随代码评审。

除 `mock-` 这一条约定外，插件不携带其他白名单：其余策略属于各仓库的 `.betterleaks.toml`。CI 不经过闸门，也不会自动加载任何配置；在 CI 里扫描的仓库把这条约定写进自己的 `.betterleaks.toml` 并以 `-c .betterleaks.toml` 使用，闸门与 CI 的结果才一致。规则缺口应向 betterleaks 上游反馈。

执行 `git add` / `git commit` 后，再单独执行 `git push`，让扫描器看到最终提交。子模块逐个推送后，父仓库使用 `--recurse-submodules=no`。扫描范围与保守拒绝的命令形式见上文。

## 配置与升级

Claude 项目配置模板包含 `extraKnownMarketplaces` 和对象形式的 `enabledPlugins`，每个插件 ID 对应布尔值。模板默认启用三个本地插件；用户应将其合并到已有配置，而不是覆盖整个文件。

项目配置声明启用范围，不代替每位协作者安装插件。Codex 使用自己的安装与启用配置，不能直接套用 `.claude/settings.json`。具体操作统一维护在 README 和 USAGE，避免设计文档再复制一份安装示例。

插件版本由各自 `plugin.json` 管理，变更记录写入 CHANGELOG。修改已安装插件后，需要更新对应客户端的安装副本并重新加载或开启新会话；Codex hook 定义发生变化时还需重新审阅信任。仅修改源码或版本号不代表现有会话已更新。

## 验证与扩展

本地开发需 Python 3、Node.js 22.18 或更高版本、jq、bats-core 和 PyYAML。macOS 可用 `make deps` 安装 jq、bats-core 和 PyYAML；Python 与 Node 需预先安装。PyYAML 仅用于测试。

```sh
make validate
make test
```

中央 `tests/` 保存跨插件检查，各插件的 `tests/` 保存专属测试，`tests/pi/` 验证 Pi 扩展。`make test` 运行 Bats 后再运行 Node 测试。`tests/manifests-cursor.bats` 检查清单接线，不会作为技能或模型规则加载。

- `make validate` 检查 Claude 与 Cursor 的 marketplace、插件清单、Cursor hook 配置和模板的 JSON 语法，不是完整客户端 schema 或安装验证。
- `make test` 运行中央与各插件的 bats：技能 YAML、引用文件、模板格式与默认启用范围、提醒输出、扫描调用与阻断分支等。
- 技能触发、规范采纳、代理路由及费用用真实模型会话评估。`make eval` 提供评估提示，不执行模型测试。
- Codex 安装发现、受信任 hook 执行和模型行为属于不同验证层，不以其中一层通过代替其他层。

新增语言或领域时，在 `gox-code-rules/skills/` 下增加入口，按需增加 references，并同步说明与相关测试。若需要会话提醒指向新技能，还应检查提醒脚本。只有可确定判断、作用于对外操作的检查才考虑加入 `gox-guard`；每道闸门使用独立脚本与测试。

旧的按路径注入引擎、独立 Codex 打包及覆盖清单不属于当前架构。未采用方案保留在 Git / PR 历史中，不作为现行开发要求。
