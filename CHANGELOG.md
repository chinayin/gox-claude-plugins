# Changelog

本仓两个插件各自独立演进版本，按插件分节，新版本在前。

## gox-code-rules

### 0.4.0 — 2026-08-25

全面 review 后的修正（文档对齐实证 + 例外条款 + hook 微调），无规则语义变更：

- 触发机制文档对齐实测结论（`docs/mvp-findings.md`）：触发主力是 nudge + description 驱动模型显式调 Skill 工具；`paths` 为声明性字段、实测非触发主力；设计期也能触发。改 `USAGE.md` §2/§4、`README.md` 技能表，`DESIGN.md` §2.2 加实测注记。
- `frontend` 技能 description 注明当前为骨架（core rules TODO），要求向团队确认而非猜测；nudge 暂不点名 frontend（正文填充后恢复）。
- `shell` 技能补两条结构性例外：Claude Code hook 脚本 fail-open（仅 `set -u`，永远 exit 0）；测试 harness 用 `set -uo pipefail` 不带 `-e`。退出码表加注"与 getopts 惯例不同，团队内以本表为准"。
- 清理 `.kiro/steering` 迁移残留措辞：`rules.md` ×3、`config.md` ×1 的 "steering file" 改为 `references/X.md`；dangling-link bats 测试扩展覆盖 references 互引。
- 统一响应体收敛为唯一源：正文只在 `references/http.md` → "Response"（成功 `{code, message, data, metadata}`，错误 `{code, message, errors, request_id}`，可选字段为空省略）；`rules.md` → "API Design" 只留指针。
- `engineering` 技能补上游出处（andrej-karpathy-skills / karpathy-guidelines，MIT）。
- `rules.md` gomock 指明用维护中的 `go.uber.org/mock`（原 golang/mock 已归档）。
- `session-nudge.sh`：SubagentStart 时读 stdin `agent_type`，对 token-thrift 的纯只读 `cheap-reader` 跳过注入（解析失败/无输入照常注入，保持 fail-open）；nudge 末尾加 "If the Skill tool is unavailable, follow your brief instead."；bats 同步补过滤与 fail-open 用例。
- 首次实测 `engineering` 技能内容效果并记入 `docs/mvp-findings.md`：干净基座对照下，无关格式改动 4/5→0/5、自加未要求语义 3/5→0/5、完全外科手术式改动 0/5→5/5，效果集中在"简单优先/外科手术式改动"两条；未观测到回复变啰嗦。边界：N=5、注入方式强于真实加载，可能高估。

### 0.3.0 — 2026-08-21

- 新增 `go/references/http.md`：HTTP/gin 规范（engine 设置、handler 形态、ctx 传值、slog 接线、request-id/trace、中间件五件套、测试、net/http 迁移路径）。

### 0.2.1 — 2026-08

- shell 规范：中文消息里的变量展开必须加花括号（`"${var}"`），附复现、CI 掩蔽分析与 grep 门禁。

### 0.2.0 — 2026-08

- 规范提醒同时注入子代理（SubagentStart）；优化注入文案。
- go 规范：微服务项目名以 `-svc` 结尾；docs 命名例外排除 superpowers/ 命名空间。

### 0.1.0 — 2026-06

- 初始版本：engineering（Karpathy）+ go（rules/cli/config/db-migrations/scaffold）技能、SessionStart nudge、frontend 骨架、shell 技能、project-scope 启用模板、bats 测试与 MVP 触发率验证（`docs/mvp-findings.md`）。

## token-thrift

### 0.1.1 — 2026-08-25

- 措辞去除模型代际与价格硬编码（"Opus"/"$1/$5"/"40–60%" → 档位相对表述）；3k token 阈值标注为经验值。行为无变化。

### 0.1.0 — 2026-08

- 初始版本：`cheap-reader`（Haiku，只读侦察）、`careful-writer`（Sonnet，正确性敏感写入）两个 subagent + `delegate` 分流策略技能。
