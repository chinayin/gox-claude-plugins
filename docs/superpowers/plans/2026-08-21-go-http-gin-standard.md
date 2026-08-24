# go 技能补 HTTP/gin 规范（references/http.md）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans（或 subagent-driven-development）
> 按 Task 逐条执行。步骤用 `- [ ]` 追踪。
> **先读 Task 0——改动可能已经在工作树里了，不要重复劳动。**

**Goal:** 给 `gox-code-rules` 的 `go` 技能补上**唯一缺失的领域**——HTTP 服务/handler 规范
（`references/http.md`），把「团队用 gin」这条要求真正写进规范，并给出既有 `net/http` 服务的合规判定与迁移路径。

**Why now:** 2026-08-21 在 `uhomes-ai-apps/wecom-contact-portal`（Go 1.26 企微门户，29 路由 / 35 handler）
上做规范核查时发现的空缺，证据如下，**不需要重新审计**：

- `skills/go/references/rules.md` 的「API Design」「Microservice Governance」两节只规定**线上契约**
  （RESTful / `/v1` / snake_case / 统一响应体 / `/health/live|ready` / 限流熔断 / trace 透传），
  **一个字都没提 HTTP 框架**。
- `rules.md` 末尾「Use gox for: log, config, discovery, trace, metrics, middleware, transport」是**愿景清单**：
  实测 gox **v1.0.0 只有 `cli/ config/ log/ idgen/ validator/` 五个包，没有 transport/middleware**，
  其 `go.mod` 也不含 gin。**没有一个「gox 官方 HTTP 层」在等业务对接。**
- 后果：业务侧「该用什么框架、handler 怎么写、请求域数据放哪、handler 怎么测」全靠各自发挥；
  而 `go` 技能的 5 份 references 里 CLI/config/迁移/脚手架都有正文，唯独最高频的 HTTP 没有。

**Scope:** 只动 `gox-claude-plugins` 仓。不动任何业务仓。

---

## Global Constraints

- 工作目录：**源码仓** `~/Sites/github/chinayin/golibs/gox-claude-plugins`
  （remote `git@github.com:chinayin/gox-claude-plugins.git`）。
  ⚠️ **绝不要改 `~/.claude/plugins/marketplaces/chinayin`**——那是 `/plugin` 的**安装副本**，
  更新时会在该目录 `git pull`，改在那里既不是源，还会被下次更新冲掉。
  正确路径是：改源码仓 → 提交 → 合并 main → 下次 `/plugin` 更新自动拿到新版。
- **references 正文用英文**（与 `rules.md`/`cli.md`/`config.md`/`db-migrations.md` 一致）；
  `SKILL.md` 里"回复与代码注释用中文"的要求是给使用者的，不是给 references 本身的。
- **单一源，不复制**（`docs/DESIGN.md` §1 已锁定）：规则正文只在 `skills/go/references/http.md`，
  不许在 README/USAGE/DESIGN 里抄条款，那些地方只放**指针**。
- **不得把既有 `net/http` 服务判为违规**：规范要能被现存服务通过（详见 Task 1 的「豁免条款」），
  否则会逼出一批为合规而做的高风险重构。
- 提交信息用中文 + 约定式前缀（仓内既有风格：`docs(shell-rules): …；版本 0.2.1`）。
- 验收闸门：`make validate && make test`（bats 20 项）必须全绿。**特别注意 `tests/skills.bats`
  有「每个 `references/*.md` 必须被同目录 SKILL.md 索引」的用例**——新增 reference 必须同步改索引，否则红。

---

## Task 0: 先确认工作树状态（必做第一步）

2026-08-21 的会话里**这套改动已经全部落到工作树并跑绿了，但没有提交**。先确认还在不在：

- [ ] **Step 1: 看状态**

```bash
cd ~/Sites/github/chinayin/golibs/gox-claude-plugins && git status --short
```

期望看到（7 项）：

```
 M README.md
 M README.zh-CN.md
 M USAGE.md
 M plugins/gox-code-rules/.claude-plugin/plugin.json
 M plugins/gox-code-rules/skills/go/SKILL.md
 M plugins/gox-code-rules/skills/go/references/rules.md
?? plugins/gox-code-rules/skills/go/references/http.md
```

- [ ] **Step 2: 分叉**
  - **改动都在** → 跳过 Task 1–5，直接做 **Task 6（验收）+ Task 7（提交/PR）**，
    但仍要按 Task 1 的「必含条款清单」逐条 review 一遍 `http.md`，以及处理 **Task 8 的两个待定决策**。
  - **改动没了**（被 `git pull` 冲掉 / 换机器）→ 按 Task 1–7 从零实现。清单是完备的，
    照着写即可，不需要回到业务仓重新审计。

---

## Task 1: 新增 `skills/go/references/http.md`

**Files:**
- Create: `plugins/gox-code-rules/skills/go/references/http.md`

**Interfaces:**
- Produces：`go` 技能的第 6 份 reference，被 Task 2 的 SKILL.md 索引引用、被 Task 3 的 `rules.md` 指针引用。

**必含章节与条款**（每条都来自真实项目验证过的踩坑，别删条款，可改措辞）：

- [ ] **Step 1: 开篇定位**——说明「线上契约在 `rules.md`，本文是 handler 级规范」，避免与 `rules.md` 重复。

- [ ] **Step 2: `## Framework`**
  - 新 HTTP 服务 **MUST** 用 `github.com/gin-gonic/gin`。
  - **`gin.New()`，绝不 `gin.Default()`**——`Default()` 挂 gin 自带 logger/recovery，
    既违反「业务只用 log/slog」，其 recovery 的响应体也不符合统一错误格式。
  - **豁免条款（必须写，别删）**：既有 `net/http` + Go 1.22 `ServeMux` 服务只要满足 `rules.md`
    的 API 契约即为**合规**；不得仅为风格统一而迁移，更不许夹在功能分支里顺手迁。
  - 点明 gox 无 HTTP transport，别等、也别自造路由。

- [ ] **Step 3: `## Engine Setup` (MUST)**——带代码块。四个必须显式设置的项，
  每个都要写清「不设 = 对外行为变更」：`gin.SetMode(ReleaseMode)`、`RedirectTrailingSlash=false`、
  `RedirectFixedPath=false`、`HandleMethodNotAllowed=true`，外加 `http.Server.ReadHeaderTimeout`。
  强调 `*gin.Engine` 是 `http.Handler`，优雅退出仍走 `http.Server.Shutdown(ctx)`，禁 `engine.Run()`。

- [ ] **Step 4: `## Routing` (MUST)**
  - **路由集中在 `cmd/<app>/run.go` 一处注册，禁 handler 包自注册**。
    理由写成**安全属性**：「哪些端点在鉴权中间件后面」必须读一个文件就能回答，
    而不是 grep 十个包。据此点名不推荐 `RegisterRoutes(g *gin.RouterGroup)` 模式。
  - 复数资源名 + 版本前缀；路径参数 `:name`；**路由匹配不等于校验**，handler 内必须再校验。
  - **路由树坑**：gin 是 httprouter 血统，同层级「静态段 vs 通配段」（`/v1/users/export`
    与 `/v1/users/:id` 并存）历史上注册期 panic 且跨版本行为不一致——加第一条这种路由前先用
    20 行 spike 验，撞了就改路径形状（`/v1/users:export`），不要重构资源模型。
  - 遗留 `http.Handler`（webhook/回调）用 `gin.WrapH` 包，不值得改写。

- [ ] **Step 5: `## Handler Shape` (MUST)**——带代码块：结构体 + 构造函数注入 +
  **消费侧最小接口**（接口定义在 handler 包、只列本包用到的方法，repo 隐式满足）+
  必需依赖为 nil 时 `panic`。禁把 handler 写成闭包/裸函数（**无法注入 stub ⇒ 无法单测**）。
  DTO 每文件自带、snake_case tag、不直接返回领域实体。

- [ ] **Step 6: `## Request-Scoped Values: Context, Not c.Set` (MUST)**——带中间件代码块。
  身份 / 权限范围 / request-id / trace-id 一律走 `c.Request.Context()`，
  **禁 `c.Set` / `c.MustGet` 传业务数据**。三条理由按权重排序：
  ① 业务与 repo 层签名是 `ctx context.Context`，只有 ctx 能不加参数一路传到底；
  ② `c.MustGet` 类型不匹配是 panic，而 `ScopeFrom(ctx) (scope, ok)` 能把中间件链断裂报成 500；
  ③ handler 与框架解耦。结论句：`*gin.Context` 只做 HTTP 层的事（取参、写响应、Abort）。

- [ ] **Step 7: `## Response` (MUST)**
  - 全服务**只有一对** writer：`WriteOK(c, data)` / `WriteErr(c, httpStatus, code, msg)`。
  - **禁裸 `c.JSON` / `c.AbortWithStatusJSON` 拼 body**——出现一处，格式漂移就无法 grep 收敛。
  - `request_id` **必须**由 request-id 中间件经 ctx 提供，禁在写出点各自生成
    （真实项目里就是两处各自 `rand`，同一请求报两个 id）。
  - 错误码表（作为可扩展的规范表落进文档）：`4000` / `4001`·`4010` / `4011` / `4030` /
    `4004`·`4040` / `5000` / `5010` / `5030`。
  - **禁回传原始 error**：服务端 `slog.*Context` 记因，客户端拿通用提示。

- [ ] **Step 8: `## Parameter Handling`**
  - **禁 `c.DefaultQuery`**——它把「显式传空」和「没传」混为一谈，有端点依赖这个区分。带代码块示范显式判空。
  - `ShouldBindQuery/JSON`（+ `gox/validator`）只可用于纯展示字段。
  - **凡是会进 SQL 的枚举（排序列 / 维度 / 指标 / 方向）必须过白名单映射到常量**；
    binding tag 只校验**格式**、不校验**值域**，永不把请求原值拼进查询。
  - 无界列表用游标分页，不用 offset。

- [ ] **Step 9: `## Middleware` (MUST)**——五件套 + 顺序：
  ① Recovery（**必须输出统一错误体**，gin 自带的不是）；② Request ID（生成 → ctx → 回写 `X-Request-Id`）；
  ③ Access log（只用 slog，带 trace id）；④ Auth/scope（按 Step 6 的 ctx 规则）；
  ⑤ **入口限流 + 熔断**（`rules.md` 的 MUST，**出向客户端限流不算**）。
  外加一条硬规则：**中间件契约违反 = 500，不得降级放行**——handler 需要 scope 而 ctx 里没有，
  说明路由漏挂中间件，那是部署期 bug；返空结果会把接线错误变成数据泄漏或静默错答。

- [ ] **Step 10: `## Cookies and Redirects`**
  - **禁 `c.SetCookie`**：位置参数签名表达不了 `SameSite`，而会话 cookie 必须
    `HttpOnly` + `SameSite=Lax`(或更严) + `Secure`。改用 `http.SetCookie(c.Writer, &http.Cookie{...})`。
  - 重定向用 `c.Redirect`；OAuth `state` 必须一次性短 TTL cookie + `subtle.ConstantTimeCompare`。

- [ ] **Step 11: `## Files and Streaming`**——优先 **302 到预签名 URL**，别拿服务代理字节
  （省掉 Range、超时、内存压力）；必须代理时用 `http.ServeContent(c.Writer, c.Request, …)`
  而非 `c.File`/`c.DataFromReader`（前者正确处理 Range/ETag/条件请求）。

- [ ] **Step 12: `## Concurrency`**——`*gin.Context` 响应写完即回池，跨 handler 生命周期的 goroutine
  **必须 `c.Copy()`**；更好的做法是**handler 内不起 goroutine**，交给 job/worker 框架
  （handler 里 fire-and-forget 没重试、没可观测、发版即丢）。外部调用超时按 `rules.md`（内 10s / 外 30s）
  且派生自请求 ctx。

- [ ] **Step 13: `## Testing` (MUST)**——走 `engine.ServeHTTP(rec, req)` 黑盒 + `httptest`；
  **禁 `gin.CreateTestContext`**：它绕过路由与中间件链，而 handler 契约的很大一部分**就是**中间件行为
  （缺 scope→500、缺 token→401）；且它要手填 `c.Params`，等于把「路由一套、测试另一套」的漂移换个地方再踩。
  给出 `newTestEngine(h)` 辅助函数样板；集成冒烟用 `httptest.NewServer(engine)`。

- [ ] **Step 14: `## Migrating an Existing net/http Service to gin` (conditional)**
  - 前置：**只在独立分支做，禁与功能任务并行**。
  - 实测基线（29 路由 / 35 handler / 2.9k 行 handler / 4.3k 行 handler 测试）：**约 2.5–3 人天**；
    **成本驱动项不是 handler，而是测试里直接 `h.HandleX(rec, req)` 的调用点**。
  - 六步保绿顺序：① 先在 net/http 形态补 recovery/request-id/access-log；
    ② 引擎内部换 gin 但**保留 `Handle(pattern string, http.Handler)` 接缝**，`{x}`→`:x` + `gin.WrapH`
    （**这一步做完全部 handler/中间件/测试不动且全绿，gin 的引入被压到一个文件**）；
    ③ 并存两套 writer，复用同一 body 结构体保证字节级一致；
    ④ 中间件转换，**身份继续放 `c.Request.Context()`**（这才是让第 5 步不翻倍的关键）；
    ⑤ handler **一文件一提交**，从小到大，落一个就摘掉该路由的 `WrapH`；
    ⑥ 改测试、删接缝，确认 `gin.DefaultWriter` 没直写 stdout、Recovery 输出统一体。
  - **语义差表**（对比 Go 1.22 `ServeMux`，每行都是对外可见变更）：
    方法不匹配 405→404 / 尾斜杠 404→301 / 大小写与多斜杠 404→301 / 静态+通配同层 支持→可能 panic /
    panic 断连→非规范 500 体 / 无访问日志→`gin.Default()` 直写 stdout。
    末句提醒：翻前两条之前先 grep 前端对 405、404 的分支。

---

## Task 2: `skills/go/SKILL.md` 索引与激活

**Files:**
- Modify: `plugins/gox-code-rules/skills/go/SKILL.md`

- [ ] **Step 1: 索引表加一行**（放在 `rules.md` 行之后、`cli.md` 行之前——HTTP 比 CLI 高频）：

```
| Writing/designing **HTTP** services: routing, handlers, middleware, request/response, handler tests (gin) | `references/http.md` |
```

⚠️ `tests/skills.bats` 的「no orphan references」用例就查这个，漏了必红。

- [ ] **Step 2: frontmatter `description` 里加上 HTTP/gin**，让技能在写 handler 时也能被命中：
  `… Go code in this repo — HTTP services and handlers (gin), CLI commands (cobra), …`

- [ ] **Step 3: `## Core rules` 加一条**（只放最高优的两句，正文仍在 http.md）：

```
- HTTP services use gin: `gin.New()` (never `gin.Default()`); request-scoped identity lives in
  `c.Request.Context()`, **never** `c.Set`/`c.MustGet`.
```

---

## Task 3: `references/rules.md` 加指针

**Files:**
- Modify: `plugins/gox-code-rules/skills/go/references/rules.md`

- [ ] **Step 1:** 在「API Design」小节末（`- Timestamps: ISO 8601 UTC` 之后）加一段指针，
  照抄 `cli.md` 那句的写法（`For CLI-specific conventions …, see the cli steering file.`）：

```
For handler-level conventions (framework, engine setup, routing, middleware set, ctx vs `c.Set`,
parameter whitelisting, handler tests), see the `http` steering file.
```

**不要**把 http.md 的条款抄进 rules.md（单一源）。

---

## Task 4: 版本与插件描述

**Files:**
- Modify: `plugins/gox-code-rules/.claude-plugin/plugin.json`

- [ ] **Step 1:** `version` `0.2.1` → **`0.3.0`**（新增一份 reference = feature，不是 patch）。
- [ ] **Step 2:** `description` 里的 Go 领域列表加上 HTTP：
  `Go (architecture/HTTP-gin/CLI/config/migrations/scaffold)`。
- [ ] **Step 3:** `marketplace.json` **不用改**（它不带版本号，描述也够泛）。

---

## Task 5: 文档联动（只放指针）

**Files:**
- Modify: `USAGE.md`、`README.md`、`README.zh-CN.md`

- [ ] **Step 1: `USAGE.md` 的「你想做 / 这样问 / 会用到」表加两行**（放在 cobra 那行之前）：

```
| 写 HTTP 接口 | `给 /v1/users 加个列表端点` / `这个 handler 怎么取路径参数` | go → `references/http.md` |
| 迁到 gin | `把这个 net/http 的服务迁到 gin` | go → `references/http.md`(末节) |
```

- [ ] **Step 2:** 两个 README 的技能表里 Go 那行，覆盖范围加上 gin HTTP：
  `Go architecture + gin HTTP / cobra / gox-config / goose / scaffolding …`（中文版同理）。
- [ ] **Step 3: `docs/DESIGN.md` 不动**——§4.2 那份 references 清单是 v2 设计期的历史快照
  （它连 `scaffold.md` 都没列），补一半反而更误导。要动就单独起一次「DESIGN 对齐现状」的改动。

---

## Task 6: 验收

- [ ] **Step 1:**

```bash
cd ~/Sites/github/chinayin/golibs/gox-claude-plugins
make validate   # 4 个 manifest 应全部 OK
make test       # bats：应 20 项全绿
```

期望：`ok 5 no orphan references — every references/*.md is indexed in its SKILL.md` 通过
（这条就是 Task 2 Step 1 的闸门）。

- [ ] **Step 2: 人工 review 一遍 `http.md`**，逐条对 Task 1 的必含条款清单打勾，重点确认
  **豁免条款还在**（既有 net/http 服务合规、不得为风格迁移）。
- [ ] **Step 3:** 起一个新会话、在一个 Go 仓里问「给 `/v1/users` 加个列表端点」，
  确认模型会去读 `references/http.md`（触发率是 skill-creator eval 的事，不是 bats 闸门，手动看一次即可）。

---

## Task 7: 提交与 PR

- [ ] **Step 1:** 从 `main` 起分支：`git switch -c docs/go-http-gin-standard`
- [ ] **Step 2:** 提交（中文 + 约定式前缀，与 `00986fb` 同风格）：

```
docs(go-rules): 补 HTTP/gin 规范 references/http.md；版本 0.3.0
```

正文写清三点：① 规范此前只有 HTTP 契约、无框架与 handler 级条款；
② gox v1.0.0 无 transport/middleware，故不存在可对接的官方 HTTP 层；
③ 既有 net/http 服务有明确豁免，不因本次规范而变成违规。

- [ ] **Step 3:** `git push -u origin docs/go-http-gin-standard` + `gh pr create`（仓内走 PR 流程，
  历史提交是 `Merge pull request #N`）。
- [ ] **Step 4:** PR 描述里带上 Task 8 的两个待定决策，请团队拍板。

---

## Task 8: 决策记录

- [x] **决策 1：gin 的强制力**——2026-08-24 定为**无条件 MUST，且无规模门槛**。
  「这个小到可以用 `net/http`」不是实现者能做的判断；一个路由还是五十个、内部还是对外、
  webhook 接收端、debug 口、一次性工具，全部建在 gin 上。**唯一出口是书面例外**
  （团队或项目负责人的明确指令，记录在 `docs/` 下的 ADR 或任务本身）——例外是被授予的，
  不是从「这段代码简单」推断出来的。既有 `net/http` + `ServeMux` 服务改判为
  **out of scope**（不判违规，但也不是可抄的样板），要接入看末节迁移。

  > 中间稿曾写过一节「Minimal HTTP surface」，用三条门槛（是否版本化 / 是否需鉴权 /
  > 是否进服务注册）划出可用 `net/http` 的小面。**已删除**：判断闸门人人往对自己有利的
  > 方向解，等于把规范要消灭的「各自发挥」请回来。

- [x] **决策 2：日志与 gox 的结合方式**——`gox/log.Logger` 内嵌 `*slog.Logger`，
  故规则定为「**入口只调一次 `slog.SetDefault`，HTTP 层永不调、也不收 logger 参数**」。
  HTTP 层代码因此在有/无 gox 的项目里一字不差——项目没引入 gox 就不为此加依赖，
  **靠机制而非豁免条款**实现降级。`SetDefault` 是进程级后写覆盖前写且无任何报错，
  所以 `NewServer` 里再 set 一次会静默盖掉 bootstrap 的 logger，连带丢掉 `ContextHandler`，
  使每条日志的 `request_id` / `trace_id` 一起消失。

- [x] **决策 3：`request_id` 与 `trace_id` 分开**——`trace_id` 走 W3C `traceparent` + `otelgin`
  （跨服务、不回传客户端）；`request_id` 单跳、回传响应体与 `X-Request-Id`。
  不合一的理由：`request_id` 是用户报障时截图里那串，不能挂在 otel 的采样决策上。
  两者由一个 `ContextHandler`（`slog.Handler` 从 ctx 取）自动挂到每条记录，禁在调用点手写。

- [ ] **决策 4（仍待定）：SessionStart nudge 要不要加 HTTP 路由行？**
  `hooks/session-nudge.sh` 的提示文案现在按「Go / 前端 / shell / 通用」四类路由，
  HTTP 已被「Go code」覆盖，所以本次**没改**。若发现写 handler 时技能命中率不够，
  再考虑在 Go 那行补「HTTP handlers, routing, middleware」几个词——
  改了要同步 `plugins/gox-code-rules/tests/session-nudge.bats` 的文案断言。

---

## Self-Review

- [ ] `references/http.md` 是英文，且没有把 `rules.md` 的契约条款抄一遍（单一源）
- [ ] SKILL.md 索引、description、core rules 三处都改了
- [ ] `rules.md` 只加了指针，没搬正文
- [ ] `plugin.json` 版本 0.3.0；`marketplace.json` 未动
- [ ] README ×2 / USAGE 只加指针；`docs/DESIGN.md` 未动
- [ ] `make validate` + `make test`（20 项）全绿
- [ ] 豁免条款在位——本规范不会把任何现存合规服务判成违规
- [ ] 已提交并合并 `main`（`/plugin` 更新从 remote 取，未合并的分支不会被安装副本看到）

---

## 附：来源与追溯

- 触发场景：`uhomes-ai-apps/wecom-contact-portal`（Go 1.26 / gorm / gin 未采用），
  该仓 `docs/GIN_MIGRATION.md` 是**业务侧**的迁移作业单（实测盘点、spike、逐文件切分顺序、
  「插件条款 ↔ 项目现状」对照表），与本文互为上下游：**编写约定的唯一源在本插件，业务仓不复制**。
- 本文所有条款都有该仓的真实代码位置作为出处；如需举例可回该仓 `internal/adapter/http/`。
