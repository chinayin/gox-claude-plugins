# Changelog

本仓各插件独立演进版本，按插件分节，新版本在前。第三方引用不钉版本，只记接入与变更。

## 第三方引用

### diagram-design 接入 — 2026-09-13

marketplace 新增 `diagram-design`（cathrynlavery/diagram-design，MIT），引用上游默认分支，不钉版本、不进默认模板。
准入清单与登记见 `docs/THIRD_PARTY.md`。

## gox-guard

### 0.1.0 — 2026-09-08

新插件：agent 侧不可逆动作的确定性闸门。每道闸一个脚本 `hooks/<闸名>.sh`，在 hooks.json 同一事件下
并列注册，文案前缀 `[gox-guard/<闸名>]`，`GOX_GUARD_SKIP=1` 整体跳过。首个闸门 `secrets`：

- 触发：PreToolUse 匹配 Bash，命令含 `git [全局选项] push` 才动作；`git stash push`、
  `git log | grep push` 不算。只拦 push 不拦 commit。
- 区间：`HEAD --not --remotes`，`--all` / `--mirror` 时扩为 `--branches --not --remotes`。
  没有待推送提交不调扫描器。
- 扫描器：betterleaks。不 pin 版本、不自动安装；缺失时拦下 push 并让模型提醒用户
  `brew install betterleaks`。SessionStart 也检查一次，缺 jq 同样处理。
- 结果：干净静默放行；有发现返回 `permissionDecision: deny`，文案为一行一条的发现列表
  （规则、文件:行、提交、fingerprint，最多 10 条）加两句裁定规则（真密钥删除并轮换 / 误报用
  `betterleaks:allow`、`.betterleaksignore` 或 `.betterleaks.toml` / 绝不加白真值）。扫描器缺失或
  出错同样 deny。
- 硬约束：`--redact` 常开，永不传 `--validation`；不要求也不生成任何配置文件；退出码永远 0。
- 分发：加入 marketplace 与 `templates/project-settings.json`；`tests/template.bats` 改为遍历
  marketplace。

## gox-code-rules

### 0.8.1 — 2026-09-22

- 修复 engineering 与 shell 的 description 中冒号导致的 YAML frontmatter 解析错误，保持描述与规范正文含义不变。
- 移除 marketplace、插件描述和 session/subagent 提醒中指向未交付 Python Skill 的声明；不新增未经团队定义的 Python 规范。
- 技能检查改用 PyYAML 解析，提醒测试验证引用的 Skill 文件确实存在；同步纠正 paths 的声明性元数据说明。
- 测试直接使用已有的 `python3`；`make deps` 安装 PyYAML，不增加插件运行依赖。

### 0.7.0 — 2026-09-09

新增 `skill` 技能：写 agent 技能（SKILL.md）时的几条裁定。编写过程归官方 skill-creator，本技能只补它
没定的事，不复述。

- 命名：一个词是针对一类文件或语言的规则集（`go`、`shell`）；多词一律对象-动作
  （`cluster-deploy`、`token-rotate`），理由是资源多于动词、列表按资源聚类、所包 CLI 本身
  noun-verb；仅无对象的方法论技能动词在前。跟随兄弟技能的形式，不改已有技能名，名字不带版本后缀
  （版本放插件版本或 frontmatter `metadata`）。
- 语言：默认英文；仅当仓库指令或用户要求、或兄弟技能已是中文时用中文，一套技能一种语言。
- 环境事实（主机名、IP、账号与资源 ID、凭据）不进技能，只写从哪读。
- 周边：nudge 两个变体各加一行指向 `gox-code-rules:skill`；`paths.bats` 把 `skill` 纳入需声明
  `paths` 的技能；README / USAGE 表加行。
- 触发实测（技能装进插件缓存、带 nudge、sonnet、14 条提问各一次，明细见
  `gox-code-rules-workspace/skill-trigger/`）：description 补上不含文件名的说法（新建/拆分/改名/
  评审/出版本/"该叫什么名字"）并点明命名与语言以本技能为准之后，正例 4/8 → 6/8，负例始终 0/6
  不误触发。仍漏的两条是"包一下某 CLI 的日常操作"和"把某技能拆开"，模型把它们看成封装与重构任务。

### 0.6.1 — 2026-09-06

shell 技能的脚本输出文案统一改英文（规则本身不变，改的是输出语言约定）：

- 状态前缀 `错误:` / `警告:` 改为 `Error:` / `Warning:`；`die`/`warn` 片段、`未知选项:`、
  test.sh 汇总行 `结果:`、brace 门禁的报错文案同步改英文。理由：脚本由 agent / CI 驱动，
  输出会被 grep、diff、贴进 issue，本地化字符串既不渲染也不好匹配。
- 小节标题改为 "Status output: English plain text, no emoji, no color"，正文补一句输出语言裁定；
  技能顶部的语言约定改为"对话与代码注释用中文，脚本打印的一切用英文"。
- `$VAR` 紧跟非 ASCII 的大括号规则从"本标准强制中文消息 → 必踩"的长论证收成通用短规则
  （任何非 ASCII 字面量/注释都适用），实证细节（bash 3.2.57 / 5.3.9、`LC_ALL=C` 掩盖）保留；
  调用点示例改为英文消息，定位从"这里会踩坑"改为"照样加括号，成本为零"。门禁 grep 一行不变。

### 0.6.0 — 2026-09-04

nudge 收窄触发范围,降低会话与子代理里的重复技能加载(规则正文无变更):

- 背景:回放 95 个会话(主线约 3.1 万次、子代理约 3 万次 API 调用)发现两类浪费——(1) 一句确认可触发 `engineering + go + frontend + TDD` 四连,而实际只改前端文件;(2) 543 个子代理里 37% 在 brief 已含规范要求的情况下,收到 SubagentStart 提示后又重新调一遍 gox 技能并读 `rules.md`,每个子代理多约 2 次往返。
- SessionStart 文案:改为"按所改文件类型调技能,通常只调一个";`engineering` 仅限多文件改动/重构/设计,单文件编辑不调;明确"不为没碰的文件调技能、同一会话不重复调";派子代理时要求把适用规则(或技能名)写进 brief。
- SubagentStart 文案:独立的短版——以 brief 为准,brief 未提及且要写代码时才调 `go`/`shell`;不调 `engineering`。长度约为主会话版的三分之一。
- `frontend` 技能保留且不改(正文即将填充),nudge 仍暂不点名。
- bats:拆分两事件的文案断言;新增"子代理版长度不足主会话版一半"与"兜底行两事件皆有"用例。
- `go/references/rules.md` 拆成"核心 + 按需"(12KB → 约 6.5KB,只搬不改语义):MUST 级裁定留在 `rules.md`;复杂度三个 Pattern 示例、常量放置与包文件示例、Functional Options、Struct/Interface/Generics、陷阱示例移入新 `references/code-style.md`;CLI/DDD 目录树、Protobuf、gRPC Client、文档文件命名清单移入新 `references/service-layout.md`。`SKILL.md` 索引加两行;`http.md` 引用的 "API Design"/"Microservice Governance" 仍在 `rules.md`,无需改指。每个子代理默认加载量减半。

### 0.5.0 — 2026-08-26

- 新增 `go/references/time-and-timezone.md`：时间与时区规范（Go + GORM，不绑 MySQL 版本；
  核心不变量与语义分类引擎通用，SQLite 差异单独注明）——UTC 存储不变量、
  `DATETIME`/epoch/`TIMESTAMP` 选型裁定、三类时间语义、Go 边界规则（`ParseInLocation`、
  禁 `time.Local`）、GORM auto-timestamp 三个盲区与两层防御、DSN 用 `mysql.Config` +
  `FormatDSN()` 程序化生成（转义串只作粘贴用途，防手抄错）、API 契约、新表 checklist。
  行文按"裁定 + 最小理由"收紧控 token；正文无 emoji（对齐 shell 规范同款要求）。
  源自实际项目的时区统一治理经验，已去项目化（事故引用匿名化、项目名改通用表述）。
- `go/SKILL.md` 索引表加对应一行（与 db-migrations 平级，按需加载）。
- `db-migrations.md` 补时间列指针（规则区 + checklist）：类型与时区规则唯一源指向
  time-and-timezone.md，禁 `DEFAULT/ON UPDATE CURRENT_TIMESTAMP`；存量表加时间列用
  NULL/回填满足"新列必须有默认值"规则，堵住"只读迁移规范就写出 CURRENT_TIMESTAMP"的口子。

### 0.4.0 — 2026-08-25

全面 review 后的修正（文档对齐实证 + 例外条款 + hook 微调），无规则语义变更：

- 触发机制文档对齐实测结论（`docs/MVP_FINDINGS.md`）：触发主力是 nudge + description 驱动模型显式调 Skill 工具；`paths` 为声明性字段、实测非触发主力；设计期也能触发。改 `USAGE.md` §2/§4、`README.md` 技能表，`DESIGN.md` §2.2 加实测注记。
- `frontend` 技能 description 注明当前为骨架（core rules TODO），要求向团队确认而非猜测；nudge 暂不点名 frontend（正文填充后恢复）。
- `shell` 技能补两条结构性例外：Claude Code hook 脚本 fail-open（仅 `set -u`，永远 exit 0）；测试 harness 用 `set -uo pipefail` 不带 `-e`。退出码表加注"与 getopts 惯例不同，团队内以本表为准"。
- 清理 `.kiro/steering` 迁移残留措辞：`rules.md` ×3、`config.md` ×1 的 "steering file" 改为 `references/X.md`；dangling-link bats 测试扩展覆盖 references 互引。
- 统一响应体收敛为唯一源：正文只在 `references/http.md` → "Response"（成功 `{code, message, data, metadata}`，错误 `{code, message, errors, request_id}`，可选字段为空省略）；`rules.md` → "API Design" 只留指针。
- `engineering` 技能补上游出处（andrej-karpathy-skills / karpathy-guidelines，MIT）。
- `rules.md` gomock 指明用维护中的 `go.uber.org/mock`（原 golang/mock 已归档）。
- `session-nudge.sh`：SubagentStart 时读 stdin `agent_type`，对 token-thrift 的纯只读 `cheap-reader` 跳过注入（解析失败/无输入照常注入，保持 fail-open）；nudge 末尾加 "If the Skill tool is unavailable, follow your brief instead."；bats 同步补过滤与 fail-open 用例。
- 首次实测 `engineering` 技能内容效果并记入 `docs/MVP_FINDINGS.md`：干净基座对照下，无关格式改动 4/5→0/5、自加未要求语义 3/5→0/5、完全外科手术式改动 0/5→5/5，效果集中在"简单优先/外科手术式改动"两条；未观测到回复变啰嗦。边界：N=5、注入方式强于真实加载，可能高估。

### 0.3.0 — 2026-08-21

- 新增 `go/references/http.md`：HTTP/gin 规范（engine 设置、handler 形态、ctx 传值、slog 接线、request-id/trace、中间件五件套、测试、net/http 迁移路径）。

### 0.2.1 — 2026-08

- shell 规范：中文消息里的变量展开必须加花括号（`"${var}"`），附复现、CI 掩蔽分析与 grep 门禁。

### 0.2.0 — 2026-08

- 规范提醒同时注入子代理（SubagentStart）；优化注入文案。
- go 规范：微服务项目名以 `-svc` 结尾；docs 命名例外排除 superpowers/ 命名空间。

### 0.1.0 — 2026-06

- 初始版本：engineering（Karpathy）+ go（rules/cli/config/db-migrations/scaffold）技能、SessionStart nudge、frontend 骨架、shell 技能、project-scope 启用模板、bats 测试与 MVP 触发率验证（`docs/MVP_FINDINGS.md`）。

## token-thrift

### 0.1.1 — 2026-08-25

- 措辞去除模型代际与价格硬编码（"Opus"/"$1/$5"/"40–60%" → 档位相对表述）；3k token 阈值标注为经验值。行为无变化。

### 0.1.0 — 2026-08

- 初始版本：`cheap-reader`（Haiku，只读侦察）、`careful-writer`（Sonnet，正确性敏感写入）两个 subagent + `delegate` 分流策略技能。
