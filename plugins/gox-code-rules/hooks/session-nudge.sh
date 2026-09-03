#!/usr/bin/env bash
# SessionStart/SubagentStart 轻提醒：推动模型主动使用团队规范技能
# （规则正文在各技能的 references/ 里，此处不含规则内容）。
# 事件名由 hooks.json 以 $1 传入；SubagentStart 让提醒直达每个子代理会话，
# 弥补"子代理收不到 SessionStart 注入"的缺口。
# 两个事件的文案不同：主会话版要求"按所改文件只调一个技能"；子代理版更短，
# 以 brief 为准、brief 没写才调技能——避免主会话已把规范写进 brief、子代理又重新加载一遍。
# fail-open：任何错误都 exit 0，绝不 exit 2（exit 2 会阻断会话）。
# 注意：fail-open 是 shell 技能里 hook 脚本的结构性例外——不用 set -e/pipefail。
set -u

# 事件名缺省 SessionStart（向后兼容）；非法值静默放行
EVENT="${1:-SessionStart}"
case "$EVENT" in
  SessionStart|SubagentStart) ;;
  *) exit 0 ;;
esac

# 缺 jq -> 静默放行
command -v jq >/dev/null 2>&1 || exit 0

# SubagentStart：从 stdin 的 hook 输入 JSON 读 agent_type。纯只读的
# cheap-reader 不写代码，跳过注入（此处与 token-thrift 插件的 agent 名耦合）。
# 解析失败 / 无输入则照常注入（fail-open）。
if [ "$EVENT" = "SubagentStart" ] && [ ! -t 0 ]; then
  AGENT_TYPE="$(jq -r '.agent_type // empty' 2>/dev/null || true)"
  case "$AGENT_TYPE" in
    cheap-reader) exit 0 ;;
  esac
fi

if [ "$EVENT" = "SessionStart" ]; then
  MSG=$(cat <<'EOF'
[gox-code-rules] This repo follows team engineering standards, delivered as Claude Code skills (the rules live inside the skills, not here). Before writing or designing code — including small changes — invoke the skill for the kind of file you will touch (usually exactly one):
- Go code; CLI flags; configuration, environment variables, or secrets; DB migrations; project scaffolding -> the `gox-code-rules:go` skill.
- Shell/bash scripts (.sh/.bash files, CLI/helper/CI scripts, flag parsing, stdout/stderr, exit codes) -> the `gox-code-rules:shell` skill.
- `gox-code-rules:engineering` (think before coding, simplicity first, surgical changes) only when planning a multi-file change, a refactor, or a design — not for a one-file edit.
Do not invoke skills for files you are not touching, and do not re-invoke a skill already loaded in this session.
When dispatching a subagent to write or modify code, put the applicable rules (or the skill name) in its brief so it does not have to rediscover them.
golangci-lint/CI enforce only a subset of these rules; passing lint does NOT replace consulting the skill.
If the Skill tool is unavailable, follow your brief instead.
EOF
)
else
  MSG=$(cat <<'EOF'
[gox-code-rules] This repo follows team engineering standards, delivered as Claude Code skills. Your brief should already state the standards that apply — follow it. Invoke a skill only if the brief names none and you will write code: Go code, configuration, or DB migrations -> the `gox-code-rules:go` skill; shell/bash scripts -> the `gox-code-rules:shell` skill. Do not invoke `gox-code-rules:engineering` or any skill for files you are not touching. If the Skill tool is unavailable, follow your brief instead.
EOF
)
fi

jq -n --arg ctx "$MSG" --arg ev "$EVENT" \
  '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}' \
  || exit 0
exit 0
