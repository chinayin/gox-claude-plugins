#!/usr/bin/env bash
# SessionStart/SubagentStart 轻提醒：推动模型主动使用团队规范技能
# （规则正文在各技能的 references/ 里，此处不含规则内容）。
# 事件名由 hooks.json 以 $1 传入；SubagentStart 让提醒直达每个子代理会话，
# 弥补"子代理收不到 SessionStart 注入"的缺口。
# fail-open：任何错误都 exit 0，绝不 exit 2（exit 2 会阻断会话）。
set -u

# 事件名缺省 SessionStart（向后兼容）；非法值静默放行
EVENT="${1:-SessionStart}"
case "$EVENT" in
  SessionStart|SubagentStart) ;;
  *) exit 0 ;;
esac

# 缺 jq -> 静默放行
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(cat <<'EOF'
[gox-code-rules] This repo follows team engineering standards, delivered as Claude Code skills (the rules live inside the skills, not here). Before writing or designing ANY code — even a small/obvious-looking change (reading one env var, one prop or style tweak, a tiny one-off script) — invoke the skill matching the task:
- Go code; CLI flags; configuration, environment variables, or secrets; DB migrations; project scaffolding -> the `gox-code-rules:go` skill.
- Frontend code (React/Vue components, TypeScript/JavaScript, CSS/SCSS styling, state management, build/tooling config) -> the `gox-code-rules:frontend` skill.
- Shell/bash scripts (.sh/.bash files, CLI/helper/CI scripts, flag parsing, stdout/stderr, exit codes) -> the `gox-code-rules:shell` skill.
- General engineering approach (think before coding, simplicity first, surgical changes) -> the `gox-code-rules:engineering` skill.
When dispatching a subagent to write or modify code, state the required skill in its brief.
golangci-lint/CI enforce only a subset of these rules; passing lint does NOT replace consulting the skill.
EOF
)

jq -n --arg ctx "$MSG" --arg ev "$EVENT" \
  '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}' \
  || exit 0
exit 0
