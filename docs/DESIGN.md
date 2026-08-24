# gox-claude-plugins 设计文档(v2 · 技能方案)

> 团队内部 Claude Code 规范分发基建。单一权威文档,供复盘与继续深入。
> 状态:**v2 经官方规范核准,改为 Agent Skills 方案,待按此重构实现**(2026-06-19)。
> v1(hook/routing.json/bash 方案)已被本版取代,保留于 §14 供复盘。

---

## 0. 演进史(为什么走到 v2)

1. **goxctl 三层模型**:规则单一来源 `.kiro/steering/`,由 `goxctl claude` 同步进各 repo,
   同时服务 Kiro + Claude Code;难点是把 Kiro front-matter 触发语义编译成 CC 原生机制。
2. **收窄为 CC 插件**:放弃 Kiro 双目标,只把 Claude Code 服务到极致;规则正文打进插件
   (插件仓即唯一源),从 org marketplace 分发,零写用户 repo。
3. **v1 hook 方案**:用 SessionStart + PreToolUse hook + `routing.json` + bash 引擎按后缀/路径注入规则。
4. **双评审 + 官方文档核准后的关键反转**(导致 v2):
   - `enabledPlugins` **支持 project scope**(官方团队推荐做法)→ 作用域靠"团队 repo 提交
     `.claude/settings.json`"收敛,**不需要运行时 repo 闸门**。
   - **command 与 skill 已合并**(官方:"Custom commands have been merged into skills")→
     一个"命令"就是带 `disable-model-invocation: true` 的技能。无需两套机制。
   - 技能 frontmatter 原生支持 **`paths` glob 限定自动激活** → "写 `.go` 才加载 Go 规范"
     **一行 frontmatter 即可,不需要自写 PreToolUse hook / bash / routing.json**。
   - 真正的"强制"本就该靠 **CI/lint/PR gate**(确定性硬层);会话内规则是"软层引导"。
   → 结论:**激活层改用 Agent Skills,插件做成纯技能(零 hook),hook/routing 方案废弃。**

### 已锁定决策(v2)

| 决策点 | 结论 |
|---|---|
| 目标工具 | 仅 Claude Code |
| 规则正文住哪 | 打进插件 `skills/.../references/`(插件仓即唯一源,零副本) |
| 激活机制 | **Agent Skills 为主**(`paths` 自动激活 + `description` 模型自调 + 渐进披露)+ **一个薄 SessionStart 提示 hook**(只提示用技能、不含规则正文)。依据:真实测试激活率~2/3,薄提示兜住漏触发与设计期(见 `docs/mvp-findings.md`) |
| 对用户 repo 写入 | 零写入 |
| 强制力 | 会话内技能 = **软层引导(概率)**;真强制 = **CI / golangci-lint / PR gate(硬层)** |
| 代码规范粒度 | 一个 `go` 技能管所有 Go(架构+cli+config+db),内部 `references/` 分文件 |
| 作用域收敛 | **project-scope 启用**(团队 repo 的 `.claude/settings.json`),非运行时闸门 |
| 分发 | org marketplace `chinayin` + project-scope `enabledPlugins`(+ Managed force-enable 强制) |
| goxctl-claude | CC 同步角色退役 |

### 命名(最终)

| 对象 | 名称 |
|---|---|
| 仓库 | `chinayin/gox-claude-plugins` |
| marketplace | `chinayin` |
| 插件:代码规范 | `gox-code-rules`(含 `go` 技能;未来加 `node`/`python` 技能) |
| 插件:产品需求(未来) | `gox-prd` |
| 前缀 | `gox-` |

---

## 1. 架构总览

一个 **marketplace monorepo**,仓内 `plugins/` 放多个**纯技能插件**(不含 hook)。
每个插件自带规则正文(在技能的 `references/` 下)+ 技能的 frontmatter 激活声明,对用户 repo 零写入。

```
gox-claude-plugins/
  .claude-plugin/marketplace.json        # name: chinayin
  plugins/
    gox-code-rules/
      .claude-plugin/plugin.json
      hooks/
        hooks.json                       # SessionStart → 薄提示
        session-nudge.sh                 # 只注入"用 go/engineering 技能"的提示,不含规则正文
      skills/
        engineering/
          SKILL.md                       # 通用行为准则(Karpathy)
        go/
          SKILL.md                       # Go 入口:description + paths + 索引
          references/
            rules.md  cli.md  config.md  db-migrations.md  scaffold.md
        # 未来:node/  python/
    gox-prd/                             # 未来:产品需求技能
      .claude-plugin/plugin.json
      skills/prd/SKILL.md
  docs/DESIGN.md
```

**设计原则**
1. 知识单一源:规则正文只在技能的 `references/`,不复制。
2. 激活声明集中在技能 frontmatter(`description` + `paths`),不散落。
3. 软/硬分层:会话内技能软引导;CI/lint 硬强制。
4. 对用户 repo 零副作用;仅一个薄 SessionStart 提示 hook(只回显固定提示文本、fail-open、绝不 exit 2),信任面仍小。

---

## 2. 激活模型(核心)

技能用官方"**渐进披露**"三层 + 两种触发,正好覆盖我们要的全部场景。

### 2.1 三层加载(省 token 的关键)

| 层 | 内容 | 何时在上下文 |
|---|---|---|
| **metadata**(`name`+`description`,≤1536 字符) | "这是什么、何时用" | **永远在**——模型据此决定调不调 |
| **SKILL.md 正文** | 概览 + "何时读 references 里哪份"的索引 + 可内联最关键铁律 | 技能**激活时** |
| **`references/` 细节文件** | 各领域详规 | 模型**按索引、按当下任务**读哪份才加载哪份 |

### 2.2 两种触发(对应规则的不同高度)

- **`paths` 自动激活(按文件)**:技能 frontmatter 写 `paths: "**/*.go, go.mod, go.work"`,
  则**只在处理 Go 文件时自动激活**。这是 v1 想用 PreToolUse hook 手搓的东西的官方原生替代——
  "写 Go 才加载 Go 规范""编辑 `cmd/` 才看 cli"由 `paths` + SKILL.md 索引共同实现。
  > **实测注记(2026-06-20,CC 2.1.183)**:端到端验证**未观察到** `paths` 自动注入生效;
  > 实际触发由 nudge + `description` 驱动模型显式调 Skill 工具(见 `docs/mvp-findings.md`)。
  > `paths` 保留为声明,不承担触发。
- **`description` 模型自调(按意图)**:模型在**设计/规划阶段**(还没编辑文件)就能因 description 匹配
  自己把技能调出来——这覆盖了 v1 头疼的"设计期无触发"问题。
- **`disable-model-invocation: true`(手动)**:= 旧"命令"。只有用户 `/插件名:技能名` 能调,
  模型不自动调。用于刻意发起、有副作用的流程(如某些 PRD 操作)。

### 2.3 确定性的诚实定位

技能触发(`description` 自调、`paths` 自动加载)**仍是模型参与的、概率性的**——这点和 v1 批评
Cursor glob 同类。**所以技能只承担"软引导"。** 真正"必须遵守"由确定性硬层兜底:
**`golangci-lint` / 格式化 / CI / PR review**。文档不宣称技能能"强制统一规范",只宣称"高概率在场引导"。
这与原则 3 一致,也是放弃 v1 那套为"确定性"硬搓的 hook 复杂度的依据。

### 2.4 薄 SessionStart 提示(兜住技能欠触发)

真实测试(`docs/mvp-findings.md`)显示技能在真实编码场景激活率 ~2/3——好,但仍有 ~1/3 漏(尤其琐碎任务),且设计/意图期靠 description 偏弱。故加一个**薄 SessionStart 提示 hook**(`hooks/session-nudge.sh`):
- 每会话注入**一句固定提示**:"本仓遵循团队规范;写/设计代码用 `gox-code-rules:go` / `:engineering` 技能;最终强制以 golangci-lint/CI 为准"。
- **只提示、不含规则正文**(正文仍只在技能 `references/`,单一源不破)。
- fail-open、绝不 exit 2、缺 jq 静默退出。
- 作用:把模型推向技能(提升那 ~1/3 漏触发与设计期的命中),而不重塞规则、不回到 v1 的按文件注入引擎。
这是"技能为主 + 薄确定性提示"的混合,介于纯技能(欠触发)与 v1 重 hook(过度)之间。

---

## 3. SKILL.md 规范(官方,权威)

**目录**:技能 = 一个目录,`SKILL.md` 为入口;支撑文件放 `references/`(文档)/`scripts/`/`assets/`。
**插件内路径**:`<plugin>/skills/<name>/SKILL.md` → 调用名 `/<插件名>:<目录名>`。

**frontmatter 字段**:

| 字段 | 必需 | 说明 |
|---|---|---|
| `name` | 否 | 显示名,默认取目录名 |
| `description` | 推荐 | 做什么 + 何时用;**与 `when_to_use` 合计被截到 1536 字符**,关键用例写前面;略"push"以防欠触发 |
| `when_to_use` | 否 | 追加触发语境/示例 |
| `paths` | 否 | glob,限定仅在处理匹配文件时自动激活(逗号分隔或 YAML 列表) |
| `disable-model-invocation` | 否 | `true` = 仅用户手动 `/` 调 |
| `allowed-tools`/`disallowed-tools` | 否 | 技能激活时的工具权限 |
| `effort` | 否 | 覆盖会话 effort |

---

## 4. 各技能设计

### 4.1 `engineering`(通用行为准则)
```yaml
---
name: engineering
description: 团队通用工程准则(Karpathy:先想后写、简单优先、外科手术式改动、目标驱动)。编写、审查或重构任何代码前都应参考,即使用户未明说"规范"。
---
```
正文 = Karpathy 四原则正文(从上游 karpathy-guidelines 抄入,MIT,注明出处;不引外部 marketplace 依赖)。
无 `paths`(普遍适用)。**注**:技能本质按需加载;若要 engineering "每会话第一轮就常驻",见 §13 开放问题。

### 4.2 `go`(Go 架构 + 编码,一个技能管全部)
```yaml
---
name: go
description: 团队 Go 架构与编码规范。设计或编写本仓 Go 代码、CLI 命令(cobra)、配置(viper)、数据库迁移、Makefile/CI 脚手架时务必使用——只要在动 Go 代码就该参考,即使用户没说"规范"。
paths: "**/*.go, go.mod, go.work"
---
```
正文 = 概览 + **索引**(替代旧 fileMatch):
> - 写任何 Go 代码 → 读 `references/rules.md`
> - 设计/写 `cmd/` 下命令(cobra)→ 读 `references/cli.md`
> - 配置(viper)→ 读 `references/config.md`
> - 数据库迁移 → 读 `references/db-migrations.md`

`references/` 四份 = 现有 steering 同名文件的正文(单一源迁入此处)。

### 4.3 `gox-prd`(未来,独立插件)
PRD 撰写/骨架生成做成技能;按需可设 `disable-model-invocation: true` 让用户 `/gox-prd:new` 手动发起。
与 `gox-code-rules` 共享 marketplace,版本/激活独立。详设另开文档。

---

## 5. 分发与升级

- 加 marketplace:`/plugin marketplace add chinayin/gox-claude-plugins`(GitHub 源,相对路径源才解析)。
- **作用域收敛主路径 = project-scope 启用**:团队每个 repo 提交 `.claude/settings.json`:
  ```json
  {
    "extraKnownMarketplaces": { "chinayin": { "source": { "source": "github", "repo": "chinayin/gox-claude-plugins" } } },
    "enabledPlugins": ["gox-code-rules@chinayin"]
  }
  ```
  协作者信任该 repo 文件夹后被提示安装/启用 → **天然只在团队 repo 生效**,无需运行时闸门。
  分发该 settings 用 repo 模板 / scaffold(可由 goxctl 顺带写入)。
- **企业加固**:`strictKnownMarketplaces` 只信 `chinayin`(URL 易因尾斜杠/`.git` 差异落空,优先 `hostPattern`);
  Managed 层 `enabledPlugins` force-enable = 全员强制、不可关。
- 升级:插件打 tag、marketplace 指新版;`/reload-plugins` 或重启生效(回滚非实时,见 §10)。

---

## 6. 与 goxctl-claude 的关系

本插件落地后,`goxctl-claude` 对 CC 的同步职责退役(规则随技能走、不进 repo)。保留为历史/非 CC 残留场景。

---

## 7. 多语言扩展配方(以加 Node 为例)

1. 新增 `plugins/gox-code-rules/skills/node/SKILL.md`,`paths: "**/*.ts, **/*.js, package.json"`,正文索引。
2. 新增 `skills/node/references/*.md`。
3. 打新版 tag。完事——无引擎、无 hook 要改。

---

## 8. 强制力分层(软/硬)

| 层 | 机制 | 性质 |
|---|---|---|
| 软(会话内引导) | 技能(`paths` 自动 + `description` 自调 + 渐进披露) | 高概率在场,模型可忽略 |
| 硬(真正卡死) | `golangci-lint` / 格式化 / CI / PR review | 确定性 |

文档明确:技能负责"让模型默认知道并倾向遵循规范";"必须"由 CI/lint 兜底。两者分工。

---

## 9. 安全与治理

- 本插件仅一个**薄 SessionStart 提示 hook**(回显固定文本、fail-open、不读用户文件、不执行外部命令),信任面远小于一般带 hook 的插件;但插件机制本身仍是高信任组件,治理照旧。
- **插件仓写权限治理**:`chinayin/gox-claude-plugins` 开分支保护 + 强制 PR review;限定可 push 人员。
- 只走 GitHub 源;`strictKnownMarketplaces` 锁 `chinayin`,挡第三方 marketplace。
- Managed force-enable 时用户无法关 → 配回滚流程(§10)。
- 引第三方技能(如 karpathy 上游)**优先抄入自管**,不引外部 marketplace 依赖。

---

## 10. 测试 / 版本 / 回滚

- **测试**:技能用 skill-creator 的 eval 流程(给定真实 prompt,跑 with-skill vs baseline,看触发与产出);
  `description` 触发率用其 description 优化脚本评。无 bash 引擎可单测(已无)。
- **版本兼容**:记录插件 version × CC version;CC 若改技能 frontmatter 字段(如 `paths` 语义)需跟随并标最低 CC 版本。
- **回滚**:改 Managed/项目 `enabledPlugins` 关闭,或 marketplace 回退 tag;**生效非实时**——在场会话需
  `/reload-plugins` 或重启,事故预案要写明时延。

---

## 11. MVP 与分期(先验证假设)

未证假设:① `paths` + `description` 的**自动触发率**(模型真会在写 Go 时调 `go` 技能吗);
② 技能引导下模型对 Go 规范的**采纳度**;③ project-scope 启用的**作用域**是否如预期。

- **MVP(P0)**:`gox-code-rules` 插件,含 `engineering` + `go` 两个技能(`go` 带 `paths` 与 `references/rules.md`
  最小种子)。经 project-scope 在 3 个真实 Go repo 启用,用一周,观测上述三点 +(用 skill-creator)测 `go` 触发率。
- **P1**:把 `references/` 补全(cli/config/db 从 steering 迁入)+ 按 skill-creator eval 优化 `description`/索引。
- **P2**:加 `node`/`python` 技能;`gox-prd`。
- **P3**:Managed force-enable + `strictKnownMarketplaces` 全面铺开;CI/lint 硬层对齐(golangci-lint 规则与技能正文同源校对)。

> 决策门:P0 先证"技能自动触发够不够准"。若触发率不足,再考虑补一个极薄 SessionStart 兜底(见 §13),而非回到 v1 整套 hook。

---

## 12. 验收标准

- [ ] 编辑 `*.go` 时 `go` 技能被自动激活(`paths` 生效),模型能复述/遵循 `rules.md`。
- [ ] 设计阶段(未编辑文件)问"怎么设计这个 cmd 命令",模型能自调 `go` 技能并读 `cli.md`。
- [ ] 编辑非 Go 文件(README 等)不激活 `go` 技能。
- [ ] `engineering` 在编码/审查任务中被引用。
- [ ] 规则正文仅存在于技能 `references/`,无副本。
- [ ] 团队 repo(已 project-scope 启用)生效;未启用 repo 不生效。
- [ ] 加一门语言只需加一个 `skills/<lang>/`(SKILL.md + references),无引擎改动。
- [ ] 插件不含 hook(纯技能)。

---

## 13. 待深入 / 开放问题

- **`engineering` 要不要"永远在场"**:技能是按需加载;若要 engineering 从第一轮常驻,需一个极薄 SessionStart hook
  或写进项目 CLAUDE.md(破"零 hook/零写 repo")。**默认:做成技能(零 hook 纯净)**;若实测发现通用准则
  常被漏用,再加兜底。← 唯一可回退的取舍点。
- **`paths` 自动激活的真实可靠性**:官方说"仅在处理匹配文件时自动加载",但仍模型参与 → 用 skill-creator
  eval 量化触发率,决定是否需 description 加强或兜底。
- **SKILL.md 索引 vs `references/` 颗粒度**:索引写多细、cli/config/db 是否进一步拆,按 eval 结果调。
- **CI/lint 与技能正文同源**:golangci-lint 规则与 `rules.md` 如何保持一致(谁是源)。
- `gox-prd` 完整设计。

---

## 14. 附:v1(已取代)方案备忘(供复盘)

v1 用 **SessionStart + PreToolUse hook + `routing.json`(gitignore 语法)+ bash 引擎**按后缀/路径注入规则,
并设运行时 repo 闸门收敛作用域。**取代原因**:
- 官方 `enabledPlugins` 支持 project scope → repo 闸门多余。
- 官方技能 `paths` 原生支持按文件激活 → 自写 hook/bash/routing 多余,且省掉跨平台二进制分发、
  bash 版本(中文 bats)、fail-open 等一堆运维负担。
- command 与 skill 合并 → 无需 hook/skill/command 三套划分。
- 真强制本就该靠 CI/lint → hook 的"确定性注入"价值被弱化为软引导,技能已够。

v1 的实现产物(`hooks/inject-common.sh` 等)若已落地,按 v2 重构为技能;hook 相关文件移除。
