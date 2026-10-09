// gox-code-rules 的 pi 扩展：每次 agent 运行前把团队规范提醒放进 system prompt 的 gox-code-rules 段。
// 技能本身由 package.json 的 pi.skills 交给 pi 加载，这里只管提醒。
// 文案只属于 pi、与插件的 hooks/session-nudge.sh（Claude / Codex 共用）互不引用：pi 的技能没有插件
// 命名空间，也没有 Skill 工具，所以用裸技能名并要求读 SKILL.md。点名的技能必须在插件里存在，
// 由 tests/pi/gox-code-rules.test.mjs 校验。
// 用 system prompt 段而不是 context 事件插消息：context 的改动只对单次请求生效，段则跨轮次、
// 跨压缩一直在，文案不变时 pi 不重发。
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SECTION = "gox-code-rules";

const REMINDER = `[gox-code-rules] This repo follows team engineering standards, delivered as skills (listed among your available skills; the rules live inside them, not here). To use a skill, read its \`SKILL.md\`, then read only the \`references/\` files it points you to. Before writing or designing code — including small changes — load the skill for the kind of file you will touch (usually exactly one):
- Go code; CLI flags; configuration, environment variables, or secrets; DB migrations; project scaffolding -> the \`go\` skill.
- Shell/bash scripts (.sh/.bash files, CLI/helper/CI scripts, flag parsing, stdout/stderr, exit codes) -> the \`shell\` skill.
- Agent skills (a SKILL.md, its frontmatter, references/ or scripts/) -> the \`skill\` skill.
- \`engineering\` (think before coding, simplicity first, surgical changes) only when planning a multi-file change, a refactor, or a design — not for a one-file edit.
Do not load skills for files you are not touching, and do not re-read a skill already loaded in this session.
When dispatching a subagent to write or modify code, put the applicable rules (or the skill's SKILL.md path) in its brief so it does not have to rediscover them.
golangci-lint/CI enforce only a subset of these rules; passing lint does NOT replace consulting the skill.`;

export default function goxCodeRulesPiExtension(pi: ExtensionAPI) {
	pi.on("before_agent_start", (event) => {
		event.systemPromptOptions.sections[SECTION] = REMINDER;
	});
}
