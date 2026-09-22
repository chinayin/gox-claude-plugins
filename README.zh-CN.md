# gox-claude-plugins

Claude Code 团队插件，通过一个 marketplace（`chinayin`）分发。按需加载，不往你的 repo 写入任何内容。

[English](README.md)

## 插件

| 插件 | 用途 |
|---|---|
| `gox-code-rules` | 团队代码规范，做成 Agent Skills（Go / 前端 / Shell / 工程通则）。动相关文件时激活，只读当前任务用得到的那一篇细则。 |
| `token-thrift` | 把 token 密集的活外包给便宜模型的 subagent：读用 Haiku、写用 Sonnet、编排用 Opus。原文不进主上下文。 |
| `gox-guard` | 针对 Claude 即将执行的不可逆动作的确定性闸门，一闸一脚本，不往 repo 写任何东西。首个闸门 `secrets`：`git push` 之前用 [betterleaks](https://github.com/betterleaks/betterleaks) 扫"本地有、任何远端都没有"的那段提交，有发现就拦下这次 push。 |
| `diagram-design` | 第三方（[cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design)，MIT），引用、不拷贝，跟随上游默认分支。40 种编辑风格的图出成单文件 HTML/SVG，附导入/导出命令。按需启用，不在默认模板里。登记与准入清单见 [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md)。 |

集中到一个 marketplace，避免把规范抄进每个 repo `CLAUDE.md` 的老问题：多 repo 漂移、占用 context、归属不清。技能是会话内软引导，可能不触发；真正的强制以 `golangci-lint` / CI / PR review 为准。`gox-guard` 是其中唯一确定性的一块：它执行外部扫描器、可以阻断一次工具调用，所以在下面单独说明。

## 安装

项目级（推荐，随 git 共享）：把 `templates/project-settings.json` 并入该 repo 的 `.claude/settings.json` 并提交。协作者信任该 repo 后会被提示启用，作用域仅该 repo。完整配置见 [USAGE.md](USAGE.md)。

单机：

```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/plugin install token-thrift@chinayin
/plugin install gox-guard@chinayin
/plugin install diagram-design@chinayin   # 可选，第三方
/reload-plugins
```

`gox-guard` 还需要本机装有扫描器：`brew install betterleaks`（或 `go install github.com/betterleaks/betterleaks@latest`）。插件不会替你安装；装好之前，Claude 发起的 push 会被拦下并给出安装提示。

## gox-code-rules

| 技能 | 调用名 | 何时激活 | 内容 |
|---|---|---|---|
| 工程通则 | `/gox-code-rules:engineering` | 描述匹配（无文件限定） | Karpathy 准则：先想后写、简单优先、外科手术式改动、目标驱动 |
| Go | `/gox-code-rules:go` | 动 Go 文件（`**/*.go, go.mod...`） | Go 架构 + gin HTTP / cobra / gox-config / goose / 时间与时区 / 脚手架；细则在 `references/` 按需读 |
| 前端 | `/gox-code-rules:frontend` | 动前端文件 | React / Vue / TS / JS / 样式（骨架，正文 TODO） |
| Shell | `/gox-code-rules:shell` | 动 Shell 文件（`**/*.sh, **/*.bash`） | bash/CLI 脚本：stdout/stderr 分流、状态前缀、标准 flag、退出码、`test.sh` |
| Skill | `/gox-code-rules:skill` | 写或改 SKILL.md（`**/SKILL.md`） | 命名（对象-动作，不带版本后缀）、正文语言、不写环境事实；只补官方 skill-creator 没定的事，不复述 |

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

## gox-guard

针对 Claude 即将执行的不可逆动作的确定性闸门。每道闸是 `plugins/gox-guard/hooks/` 下的一个脚本，在同一事件下并列注册，文案前缀 `[gox-guard/<闸名>]`，`GOX_GUARD_SKIP=1` 整体跳过。什么算闸门：能用确定性规则判断、只作用于对外且难以撤回的动作、不往 repo 写东西。建议性的检查归 `gox-code-rules`；只有 CI 能判断的事留在 CI。

### 闸门：secrets

只在"密钥泄漏变得不可逆"的那一刻设闸：push。之前的编辑、暂存、提交一律不碰，日常编码不会变重。

| 事件 | 行为 |
|---|---|
| 会话开始 | 检查 `PATH` 上有没有 `betterleaks`。有：零输出。没有：一句话让模型提醒你安装。 |
| Claude 执行含 `git … push` 的 Bash 命令 | 扫 `HEAD` 上不在任何远端的提交（`--all` / `--mirror` 时扩到所有本地分支）。没有待推送提交：不扫直接放行。干净：静默放行。有发现：**拒绝**这次 push，给模型一行一条的发现列表（规则、文件:行、提交、fingerprint，最多 10 条）和两句裁定规则。 |
| 扫描器（或 `jq`）缺失、扫描器出错 | 拦下并说明原因，而不是静默放行。会静默放行的闸门等于没有。 |

拦截文案刻意压短，因为它会进主 agent 的上下文；也不附手册，模型本来就会 git。它告诉模型的只有：

1. 真密钥：从对应提交里删掉，并告诉你这个值已经进过本地历史、建议轮换。绝不把真密钥加进白名单。
2. 单行误报：在该行加 `# betterleaks:allow` 注释。
3. 已提交的误报：把 fingerprint 追加到 `.betterleaksignore`。成规律的误报（测试夹具、示例）：在 `.betterleaks.toml` 里加路径/正则白名单。两者都是普通的提交文件，会出现在 review 里。

几个值得知道的取舍：

- **拦 push 不拦 commit。** commit 是本地的、廉价的、随时能重做；拦它会让每次编辑-提交循环都变重，而且 `git add … && git commit …` 一条命令时，pre-commit 扫到的是 add 之前的索引，有漏洞。到 push 时区间是确定的。
- **不要求配置文件。** 没配置就用扫描器内置规则。repo 第一次需要白名单时再加 `.betterleaks.toml` / `.betterleaksignore`，插件永远不写它们。
- **不 pin 版本。** 只扫待推送区间，新规则不会让老提交突然报红。brew 给什么版本用什么。
- **永远脱敏，绝不联网验证。** `--redact` 常开（发现会进模型上下文与 transcript）；扫描器的在线验证功能永不开启（它会把疑似密钥发往厂商 API）。
- **覆盖边界。** 只看得到 Claude 发起的 push。你在终端手敲的 push、CI，都在它之外：仓库 CI 仍是最后一道硬闸。
- **逃生口。** 环境变量 `GOX_GUARD_SKIP=1` 跳过闸门。模型被告知只有你明确要求时才用。

## 开发

- 默认已有 `python3`。`make deps` 安装 jq、bats-core 和 PyYAML；`make validate` 校验 JSON manifest 与模板；`make test` 运行全部 bats，直接用 `python3` 解析 YAML frontmatter。PyYAML 仅供测试使用。
- 测试分层：中央 `tests/` 放跨插件检查（`manifests` / `skills` / `template`，循环 `plugins/*`，新插件自动覆盖）；插件专属测试放 `plugins/<name>/tests/`。`make test` = `bats tests plugins/*/tests`。
- 触发/命中率（模型是否加载技能、是否派活）不进 bats，是概率性的，用 skill-creator eval 流程评估（with-plugin vs baseline）。`make eval` 有提示。
- `gox-guard` 完全确定性，bats 用 stub 扫描器覆盖四种情形（干净 / 有发现 / 缺失 / 出错）。要跑真二进制，把 `GOX_GUARD_BIN` 指向一个 `betterleaks`，再往 hook 的 stdin 喂一段 PreToolUse JSON。
- 加语言或领域：一语言一技能，同插件内并存，各带 `description` + `paths` + `references/`。见 `docs/DESIGN.md`。

## License

[Apache-2.0](LICENSE) © 2026 chinayin.
