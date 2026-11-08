#!/usr/bin/env bash
# Cursor 会话提醒：复用正文，适配输出协议。
set -u

EVENT="${1:-SessionStart}"
case "$EVENT" in
  SessionStart) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || exit 0
DIR="$(cd "$(dirname "$0")" && pwd)" || exit 0

OUT="$(bash "$DIR/session-nudge.sh" "$EVENT" </dev/null)" || exit 0
[ -n "$OUT" ] || exit 0

printf '%s' "$OUT" | jq -c '
  .hookSpecificOutput.additionalContext
  | select(type == "string" and length > 0)
  | {additional_context: .}
' 2>/dev/null || exit 0
exit 0
