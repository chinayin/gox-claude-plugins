#!/usr/bin/env bash
# Cursor 协议适配；扫描规则、业务文案和绕过判断均由 secrets.sh 维护。
set -u

EVENT="${1:-}"
case "$EVENT" in
  SessionStart|PreToolUse) ;;
  *) exit 0 ;;
esac

# 不依赖 jq：适配失败必须保留拒绝，不能变成空输出。
adapter_error() {
  local msg='[gox-guard/cursor] Hook adapter failed. Check jq and the hook scripts before retrying.'
  if [ "$EVENT" = "PreToolUse" ]; then
    printf '{"permission":"deny","user_message":"%s","agent_message":"%s"}\n' "$msg" "$msg"
  else
    printf '{"additional_context":"%s"}\n' "$msg"
  fi
  exit 0
}

DIR="$(cd "$(dirname "$0")" && pwd)" || adapter_error
INPUT=""
if [ "$EVENT" = "PreToolUse" ]; then
  [ -t 0 ] && adapter_error
  INPUT="$(cat)" || adapter_error
  [ -n "$INPUT" ] || adapter_error
  # 原生 preToolUse 已使用 tool_input.command；兼容旧的顶层 command。
  # 缺 jq 时透传原始输入，让原脚本的无 jq 分支判断是否需要拒绝。
  if command -v jq >/dev/null 2>&1; then
    INPUT="$(printf '%s' "$INPUT" | jq -c '
      .tool_input.command = (.tool_input.command // .command)
      | if (.tool_input.working_directory // "") != "" then
          .cwd = (if (.tool_input.working_directory | startswith("/")) then
            .tool_input.working_directory
          else (.cwd // env.PWD) + "/" + .tool_input.working_directory end)
        else . end
    ' 2>/dev/null)" || adapter_error
  fi
fi

OUT="$(printf '%s' "$INPUT" | bash "$DIR/secrets.sh" "$EVENT")" || adapter_error
if [ -z "$OUT" ]; then
  # failClosed 把无输出视为失败；正常放行必须显式返回 permission。
  if [ "$EVENT" = "PreToolUse" ]; then
    printf '{"permission":"allow"}\n'
  fi
  exit 0
fi

OUT="$(printf '%s' "$OUT" | jq -sce --arg event "$EVENT" '
  if length != 1 then error("expected one hook response")
  else .[0].hookSpecificOutput end
  | if $event == "PreToolUse" and .permissionDecision == "deny"
       and (.permissionDecisionReason | type) == "string" then
      {permission: "deny", user_message: .permissionDecisionReason,
       agent_message: .permissionDecisionReason}
    elif $event == "SessionStart" and (.additionalContext | type) == "string" then
      {additional_context: .additionalContext}
    else
      error("unexpected hook output")
    end
' 2>/dev/null)" || adapter_error
printf '%s\n' "$OUT"
exit 0
