#!/usr/bin/env bash
# Cursor 会话与子代理提醒：复用正文，适配输入输出协议。
set -u

EVENT="${1:-SessionStart}"
case "$EVENT" in
  SessionStart|SubagentStart) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || exit 0
DIR="$(cd "$(dirname "$0")" && pwd)" || exit 0

# Cursor 使用 subagent_type；解析失败视为空输入，仍由原脚本决定提醒。
INPUT='{}'
if [ "$EVENT" = "SubagentStart" ] && [ ! -t 0 ]; then
  INPUT="$(jq -c '.agent_type = (.agent_type // .subagent_type)' 2>/dev/null)" || INPUT='{}'
fi
OUT="$(printf '%s' "$INPUT" | bash "$DIR/session-nudge.sh" "$EVENT")" || exit 0
[ -n "$OUT" ] || exit 0

printf '%s' "$OUT" | jq -c '
  .hookSpecificOutput.additionalContext
  | select(type == "string" and length > 0)
  | {additional_context: .}
' 2>/dev/null || exit 0
exit 0
