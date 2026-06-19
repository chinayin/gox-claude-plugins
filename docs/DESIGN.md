# gox-claude-plugins 设计文档

> 团队内部 Claude Code 规范分发基建。本文是合并需求 + 架构设计的单一权威文档,
> 供以后复盘与继续深入。状态:**经双评审修订,MVP 优先,待实现**(2026-06-19)。

---

## 评审结论与修订(2026-06-19,承重,先读)

两轮独立评审(技术事实 + 架构合理性)后的关键修订。下文 §2.5/§5 等旧表述以本节为准。

### 承重事实纠正(已用官方文档证实)
- **`enabledPlugins` 支持 project scope**(写入仓库 `.claude/settings.json`,对全体协作者生效)——
  官方团队推荐做法。**原 §2.5「CC 不支持 per-project 关插件、必须运行时 repo 闸门」的前提是错的。**
  → 作用域收敛**主路径 = project-scope 启用**(`extraKnownMarketplaces` 自动提示 + Managed force-enable 强制);
  运行时 repo 闸门**降级为兜底**(仅防 user-scope 全局启用误伤外部 repo)。
- **PreToolUse 退出码**:**仅 exit 2 阻断**工具调用;exit 1 / 崩溃 / 缺依赖 = **非阻断,继续执行**。
  → 失败策略钉死:**错误路径一律 fail-open(exit 0,绝不 exit 2)**,配 `GOX_RULES_DEBUG` 输出决策日志到 stderr。
- SessionStart 支持 `additionalContext` 注入(✅ 地基成立);marketplace monorepo 相对路径源、
  `${CLAUDE_PLUGIN_ROOT}`/`${CLAUDE_PROJECT_DIR}`、Managed force-enable + `allowManagedHooksOnly` 豁免、
  `strictKnownMarketplaces`、`permissionDecision` 均经官方文档核实属实。

### 设计修订(采纳评审)
1. **诚实的强制力分层**:hook 注入 = **软层**(高概率"在场",投递确定但模型可忽略);
   真"强制" = **硬层 = CI / lint(golangci-lint 等)/ PR gate**(确定性)。文档不再宣称 hook 能"强制统一规范"。
2. **MVP 优先,先验证假设再造引擎**:见 §11。先验证「模型采纳率」「token 成本」「作用域正确性」,
   再决定是否建 PreToolUse 路由引擎。
3. **bash 优先,推迟二进制**:routing 用「后缀 + 目录前缀 + 简单通配」够用子集;
   完整 gitignore 语义 / 小二进制**推迟到证明必要时**(跨平台分发 + 供应链成本高)。
4. **PreToolUse 必须会话级去重**(若启用):同一规范一会话只注入一次,避免 token 膨胀与噪音麻木。
5. **scope 暂两层**(common + language);**project-local 第三层砍到 P2**(YAGNI)。
6. **多插件注入叠加模型现在就定**(§4.1),避免 gox-prd 与 gox-code-rules 各自演进后打架。
7. **新增章节**:§12 安全与治理、§13 测试/版本/回滚。

---

## 0. 背景与演进(为什么是这条路)

最初的思路在 `goxctl-claude` 仓库,核心是「知识与激活解耦」三层模型:规则正文单一来源于
`.kiro/steering/`,由 `goxctl claude` 同步进各 repo,同时服务 **Kiro + Claude Code** 两个工具;
难点是把 Kiro 的 front-matter 触发语义"编译"成 Claude Code 的原生机制(`@import` + PreToolUse Hook)。
详见 `goxctl-claude/docs/ARCHITECTURE_LAYERS_AND_INDUSTRY_COMPARISON.md` 与
`CLAUDE_CODE_STEERING_INTEGRATION_GUIDE.md`。

**本项目是该思路的收窄与落地**:不再追求 Kiro/CC 双目标一致,**只把 Claude Code 服务到极致**。
收窄带来的简化:
- Kiro 适配层(L3a)和"双工具语义一致"约束整块消失。
- 规则正文直接住在插件里 → 插件仓库**本身就是唯一的源**,"不复制"原则自动成立,
  不再需要 goxctl 的同步与 lock 机制。
- 全部激活走 Claude Code 插件机制(hook/skill/command),从 org marketplace 默认启用,
  **所有 repo、所有同事零配置生效**。

### 已锁定的决策

| 决策点 | 结论 |
|---|---|
| 目标工具 | **仅 Claude Code**(放弃 Kiro 双目标) |
| 规则正文住哪 | **打进插件**(插件仓库即唯一源,零副本) |
| 对用户 repo 的写入 | **零写入**(不碰 CLAUDE.md、不碰 .kiro),全部经 hook 注入 |
| 代码规范粒度 | **一个插件管所有语言**(按文件后缀路由),非按语言拆 |
| 分发 | **org marketplace + 默认启用**(团队 settings.json 的 enabledPlugins) |
| goxctl-claude 去向 | CC 同步角色**退役**(让位给本插件) |
| 作用域闸门 | 插件**全局触发** → 仅在**公司受管 repo** 动作(git remote / 标记文件判据),否则零注入 |
| 路径匹配语法 | **gitignore 语法**(复用成熟语义,不自造 glob 方言) |
| scope 层级 | **三层**:common(全局)/ language(按栈)/ project-local(repo 内 `.claude/rules` 叠加) |
| 企业加固 | `strictKnownMarketplaces` 只信 `chinayin` 源 + Managed 层 force-enable |

### 命名(最终)

| 对象 | 名称 | 备注 |
|---|---|---|
| 仓库 | `chinayin/gox-claude-plugins` | 复数,因装多个插件 |
| marketplace | `chinayin` | 即 `plugin@chinayin` 后缀 |
| 插件1:统一代码规范 | `gox-code-rules` | 按后缀路由所有语言(Go 先行,Node/Python 后续) |
| 插件2:产品需求(未来) | `gox-prd` | 独立关注点,激活逻辑与代码规范不同 |
| 前缀 | `gox-` 全线保留 | — |

---

## 1. 整体架构

一个 **marketplace monorepo**(`gox-claude-plugins`),仓内 `plugins/` 目录下放多个**自包含**插件。
每个插件自带规则正文 + 激活逻辑,对用户 repo 零写入。

```
gox-claude-plugins/                      # marketplace 仓
  .claude-plugin/
    marketplace.json                     # marketplace 清单,name: "chinayin"
  plugins/
    gox-code-rules/                      # 插件:统一代码规范(后缀路由)
      .claude-plugin/plugin.json
      hooks/
        hooks.json                       # SessionStart + PreToolUse 声明
        inject-common.sh                 # 注入 common 准则(always-on)
        inject-by-file.sh                # 按后缀/路径注入语言规范
      rules/
        common/*.md                      # 跨语言,始终注入(karpathy 等)
        go/      rules.md cli.md config.md db-migrations.md scaffold.md
        node/                            # 未来,放进来 + 改 routing 即生效
        python/                          # 未来
      meta/routing.json                  # 「后缀/路径 → 规范」映射表(核心 DSL)
      skills/                            # 方法论类(模型按需调用)
      commands/                          # 手动加载 /gox-rules <lang>
    gox-prd/                             # 插件:产品需求(未来)
      .claude-plugin/plugin.json
      ...
  docs/
    DESIGN.md                            # 本文
```

### 设计原则(继承自三层模型)

1. **知识单一源**:规则正文只存在于 `rules/`,不复制到任何别处。
2. **激活声明集中**:触发规则收敛到一张 `routing.json`(替代原 Kiro front-matter),只定义一次。
3. **确定性优先用于 MUST**:硬规则走 hook(确定);方法论走 skill(概率,允许模型判断)。
4. **对用户 repo 零副作用**:非匹配文件不注入;不写用户文件。
5. **受管 repo 才出手**:插件全局触发,但只在公司受管 repo 动作,非受管 repo 零注入(见 §2.5)。
6. **复用成熟语义**:路径匹配用 gitignore 语法,不自造 glob 方言。

---

## 2. 激活引擎(核心)

### 2.1 两个 hook(都先过 repo 闸门)

每个 hook 第一步先跑 §2.5 的 repo 闸门:**非受管 repo 直接 `exit 0` 零注入**。

- **`SessionStart`** → 受管 repo 才注入 `rules/common/*` 全部。这是 always-on 那层,替代原 `@import`,不写用户文件。
- **`PreToolUse`(matcher: `Edit|Write|MultiEdit`)** → 取 `tool_input.file_path`,查 `routing.json`,
  命中则把规范正文(或"请先读 X")经 `hookSpecificOutput.additionalContext` 注入;非匹配零副作用。

### 2.2 routing.json(数据驱动,可单测)

`byPath` 的 `match` 用 **gitignore 语法**(成熟、有现成库,不自造方言)。

```jsonc
{
  "always": ["common/"],                    // SessionStart 全程注入(全局 scope)
  "byExt": {                                // 维度1:后缀 → 语言基线规范(stack scope)
    ".go":  ["go/rules.md"],
    ".ts":  ["node/rules.md"], ".js": ["node/rules.md"], ".tsx": ["node/rules.md"],
    ".py":  ["python/rules.md"]
  },
  "byPath": [                               // 维度2:gitignore 语法路径 → 领域规范(可叠加)
    { "match": "cmd/",                    "rules": ["go/cli.md"] },
    { "match": "Makefile",               "rules": ["go/scaffold.md"] },
    { "match": ".golangci.yaml",         "rules": ["go/scaffold.md"] },
    { "match": "*migration*",            "rules": ["go/db-migrations.md"] },
    { "match": "**/bootstrap/",          "rules": ["go/config.md"] },
    { "match": "**/config/",             "rules": ["go/config.md"] }
  ]
}
```

> gitignore 语义自带:`Makefile` 任意层 basename 命中、`cmd/` 目录前缀、`*migration*` 通配、
> `**/` 跨层——无需自己实现花括号展开 / basename-vs-path 二分。

### 2.3 路由最佳实践(踩坑都在这)

1. **后缀定基线,路径加领域,可叠加**:`cmd/server/main.go` → `.go`(rules.md)+`cmd/**`(cli.md)
   去重后一起注入。后缀=写哪种语言;路径=写这语言的哪一块。
2. **优先级 always < byExt < byPath**:越具体越靠后注入,模型对靠后内容印象更强。
3. **非匹配文件零副作用**:`README.md`/`.png` 命中不到 → 不注入、`exit 0`。体验底线,必须单测。
4. **路径匹配交给 gitignore 库**:`Makefile`/`cmd/`/`*migration*` 的 basename-vs-path、
   通配、跨层语义全由 gitignore 语义统一处理,引擎不自造方言(原文档 §7.3 的坑就此关闭)。
5. **三层 scope 叠加**:`common`(全局)+ 语言(按栈)+ **project-local**——repo 内若有
   `.claude/rules/*.md`(或 `.gox/rules/`)则一并叠加注入,允许个别项目就地扩展而不改全局插件。
6. **注入"内容"还是"请先读 X":短规范塞正文,长规范塞指令**——省 token。
7. **强制力分层**:默认 `additionalContext`(强提示);极少数 MUST 才上 `permissionDecision:"ask"`,
   别滥用,伤体验。
8. **加一门语言 = 丢 `rules/<lang>/` + 加 `byExt`/`byPath` 几条**,引擎不动。这是扩展性红利。

### 2.4 hook 内的路径定位

- `${CLAUDE_PLUGIN_ROOT}` 定位插件内文件(读 routing.json / rules)。
- `${CLAUDE_PROJECT_DIR}` 定位用户 repo 根(把 `tool_input.file_path` 转 repo 相对路径再套 gitignore 匹配)。

### 2.5 repo 作用域闸门(降级为兜底,见评审修订)

> **修订**:作用域收敛主路径已改为 **project-scope 启用**(§5)——只在公司 repo 提交
> `.claude/settings.json` 启用插件,天然只在受管 repo 生效。本闸门**降级为兜底**:仅当有人
> 在 **user scope 全局**启用插件时,防止误伤外部 repo。非主路径,实现可后置。

(以下为兜底逻辑)插件若被 user-scope 全局启用,会在每个 repo 触发;此时 hook 第一步判断
"当前是不是公司受管 repo",不是就 `exit 0` 零注入。

判据(任选 / 组合,按 `${CLAUDE_PROJECT_DIR}` 判断):

1. **git remote 属于公司 org**:remote URL 含 `github.com/chinayin/`(或公司其它 org)。
2. **标记文件存在**:repo 根有 `.gox-claude.yaml` / `.gox/` 等约定标记。
3. **项目 opt-in**:repo 的 `.claude/settings.json` 里带约定标志。

> 本质是把业界"auto-detect tech stack"的思路,前移用于"**我该不该在这个 repo 出手**"。
> 默认建议用判据 1+2 的或关系;判据可配置在 routing.json 的 `gate` 段。

---

## 3. 配置模板

### marketplace.json
```json
{
  "name": "chinayin",
  "owner": { "name": "chinayin", "url": "https://github.com/chinayin" },
  "plugins": [
    { "name": "gox-code-rules", "source": "./plugins/gox-code-rules" },
    { "name": "gox-prd",        "source": "./plugins/gox-prd" }
  ]
}
```

### plugins/gox-code-rules/.claude-plugin/plugin.json
```json
{
  "name": "gox-code-rules",
  "version": "0.1.0",
  "description": "团队统一代码规范:按文件后缀/路径自动注入对应语言规范(Go 先行,Node/Python 后续)",
  "author": { "name": "chinayin" }
}
```

### plugins/gox-code-rules/hooks/hooks.json
```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/inject-common.sh\"" }] }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit",
        "hooks": [{ "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/inject-by-file.sh\"" }] }
    ]
  }
}
```

---

## 4. Hooks / Skills / Commands 分工

| 内容类型 | 机制 | 性质 |
|---|---|---|
| 确定性硬规则(写 Go 前必读 rules、Go 版本、错误前缀…) | hooks(`rules/`) | 确定 |
| 方法论 / 模式(类 systematic-debugging) | skills(模型按 description 调用) | 概率 |
| 手动加载某规范 | commands(`/gox-rules go`) | 显式 |

---

## 5. 分发与升级

- 安装:`/plugin marketplace add chinayin/gox-claude-plugins` → `/plugin install gox-code-rules@chinayin`。
- **作用域收敛主路径 = project-scope 启用**:在公司每个 repo 提交 `.claude/settings.json`,
  写 `extraKnownMarketplaces`(指向 `chinayin/gox-claude-plugins`)+ `enabledPlugins`(开 `gox-code-rules`)。
  协作者信任该 repo 文件夹后被提示安装/自动启用 → **天然只在公司 repo 生效**,无需运行时闸门。
  分发 `.claude/settings.json` 用 repo 模板 / scaffold / 一次性脚本(可由 goxctl 顺带写入)。
- **企业加固(推荐)**:
  - `strictKnownMarketplaces`:只信任 `chinayin` 源,挡掉第三方 marketplace 供应链风险。
  - **Managed 层 force-enable**:在企业 Managed settings 里 force-enable 本插件(最高优先级、不可被覆盖);
    配合 `allowManagedHooksOnly` 时,Managed force-enable 的插件 hook 仍豁免——实现真正的全员强制、零配置。
- 升级:给插件打 tag、marketplace 指向新版;激活逻辑随插件版本统一演进,不再每 repo 各自生成。
- 缓存注意:会话中途新增 hook 可能要 `/hooks` 重载或重启;首次启用后告知用户。

---

## 6. gox-claude-plugins 与 goxctl-claude 的关系

本插件落地后,`goxctl-claude` 对 **Claude Code 的同步职责退役**——规则不再进 repo,而随插件走。
`goxctl-claude` 仓库保留为历史/非 CC 残留场景(若仍有人用 Kiro 需要把 `.kiro/steering` 物化进 repo);
新增投入集中到本插件。

---

## 7. 多语言扩展配方(以加 Node 为例)

1. 新增 `rules/node/rules.md`(及需要的领域规范)。
2. `routing.json` 的 `byExt` 加 `.ts/.js/.tsx → node/rules.md`;`byPath` 按需加 Node 领域规则。
3. 打新版 tag。完事——引擎/hook 脚本不动。

---

## 8. gox-prd 插件(未来,草图)

产品需求不参与"后缀路由",激活逻辑不同,故独立成插件:
- 可能形态:commands(`/gox-prd new` 生成 PRD 骨架)+ skills(PRD 撰写方法论)+
  对特定文档路径(`docs/prd/**`、`*.prd.md`)的 PreToolUse 触发。
- 与 `gox-code-rules` 共享 marketplace,但版本/激活独立。详细设计另开文档。

---

## 9. 验收标准

- [ ] 编辑 `*.go` 注入 Go 基线规范;编辑 `cmd/**` 叠加 cli 规范(去重)。
- [ ] 编辑 `Makefile`/`.golangci.yaml` 注入 scaffold 规范(basename 匹配)。
- [ ] 编辑迁移相关文件(`**/*migration*`)注入 db-migrations 规范。
- [ ] `common/` 每会话始终在场(SessionStart)。
- [ ] 编辑非匹配文件(`README.md` 等)无任何注入(零副作用)。
- [ ] 规则正文仅存在于 `rules/`,无副本。
- [ ] **作用域:在公司 repo(`.claude/settings.json` 已启用)生效;未启用的 repo 不生效。**
- [ ] **失败 fail-open:routing.json 写坏 / 脚本崩溃 / 缺依赖时,编辑照常进行(绝不 exit 2),debug 日志可见。**
- [ ] (若做 PreToolUse)同一规范一会话只注入一次(去重)。
- [ ] 加一门语言只需改 `rules/<lang>/` + `routing.json`,引擎不变。
- [ ] project-local 第三层 scope:P2 再验收。

---

## 10. 待深入 / 开放问题

- **routing 引擎实现选型**(最该先定):纯 bash+jq,还是嵌一个小 Go 二进制?
  改用 gitignore 语法后,**小二进制更划算**——可直接复用成熟 gitignore 库(如 `sabhiram/go-gitignore`),
  路径匹配零自研、好单测;代价是要随插件分发一个二进制(可按平台预编译进 `bin/`)。
  bash+jq 虽零依赖,但 gitignore 匹配在 shell 里仍难写对。**倾向小 Go 二进制**。
- **repo 闸门判据**最终取哪几条、是否暴露成 `routing.json` 的 `gate` 段供按 repo 调整。
- 强制力:哪些规则值得上 `permissionDecision:"ask"` 硬门禁。
- 全员分发的最终形态:团队全局 settings 模板 / 入职脚本 / 还是企业 Managed force-enable。
- gox-prd 的完整设计。

> 已关闭:自造 glob 方言规格 + 单测 —— 改用 gitignore 语义后不再需要。
> 已关闭:repo 闸门作主路径 —— 改用 project-scope 启用后,闸门仅兜底。

---

## 11. MVP 与分期(先验证假设,再造引擎)

评审核心:别先建引擎,先验证三个未证假设——① 模型对注入规范的**采纳率**;② SessionStart 一次性注入的
**token 成本**是否可接受;③ project-scope 启用的**作用域**是否如预期。

- **MVP(P0,~1 周)**:一个插件、**只 SessionStart 一个 hook、纯 bash**(`cat` 拼接 `common/` + `go/rules.md`
  注入)。在 3 个真实公司 Go repo,经 project-scope `.claude/settings.json` 启用,用一周。观测上述 3 件事 +
  对比开启前后模型对 Go 规范的遵循度。**fail-open + `GOX_RULES_DEBUG`** 从第一天就有。
- **P1(若 MVP 证明"全量注入不够精准/太贵")**:加 PreToolUse 后缀路由 + 会话级去重,bash 实现
  「后缀 + 目录前缀 + 简单通配」够用子集。把现有 Go 规范搬进 `rules/go/`。
- **P2**:加 Node/Python rules;按需引入完整 gitignore 匹配(届时再评估小二进制);project-local 第三层 scope。
- **P3**:企业 Managed force-enable + `strictKnownMarketplaces` 全面铺开;另起 `gox-prd`。

> 决策门:**P1 仅在 MVP 暴露出"SessionStart 全量注入不够用"时才做**。先证伪简单方案,再加复杂度。

## 11.1 多插件注入叠加模型(现在就定)

`gox-code-rules` 与未来 `gox-prd` 可能同时在 SessionStart/PreToolUse 注入:
- 各插件注入独立 `additionalContext` 块,**带来源前缀**(如 `[gox-code-rules]` / `[gox-prd]`)便于排查。
- **无跨插件顺序依赖**:每块自洽,不假设另一块在场或在先。
- 各插件独立做自己的会话级去重;不共享状态。
- token 预算:两插件叠加的每轮 Context cost 需在 P3 前实测(官方 `/plugin` 详情页给出每轮成本估算)。

## 12. 安全与治理(org 基建必需)

hook = 以用户权限执行任意命令;经 Managed force-enable 后,**插件作者对全员所有会话有任意命令执行权**。
故信任边界不止 marketplace 白名单:
- **插件仓写权限治理**:`chinayin/gox-claude-plugins` 开分支保护 + 强制 PR review;限定可 push 人员。
- **来源可信**:只走 GitHub 源(相对路径源仅 Git 方式有效);`strictKnownMarketplaces` 锁死 `chinayin`,
  URL 精确匹配易因尾斜杠/`.git`/协议差异落空 → 优先 `hostPattern`。
- **逃生舱**:Managed force-enable + `allowManagedHooksOnly` 时用户**无法关闭** → 必须配回滚流程(下条)。
- **二进制来源**(若 P2 引入):谁编译、如何校验 `bin/` 未被掉包,需有构建可信链。

## 13. 测试 / 版本 / 回滚

- **测试**:routing 决策做纯函数单测(给定 file_path → 期望规则集 + 零副作用);hook 脚本用 bats 测
  exit code 与 stdout JSON;端到端在真实 repo 手验 §9。
- **版本兼容**:记录插件 version × CC version 兼容矩阵;CC 若改 hook 输出格式 / `additionalContext` 字段,
  插件需跟随并标注最低 CC 版本。
- **回滚**:出问题时改 Managed/项目 settings 的 `enabledPlugins` 关闭,或 marketplace 回退 tag;
  注意**生效时延**——在场会话需 `/reload-plugins` 或重启才生效,回滚非实时,事故响应预案要写明。
