#!/usr/bin/env bash
# Antigravity（agy）PreToolUse 协议适配；扫描规则、业务文案和绕过判断均由 secrets.sh 维护。
# 输入：.toolCall.args.CommandLine 与可选的 .toolCall.args.Cwd（缺省为 .cwd）。
# 输出：拒绝为 {"decision":"deny","reason":...}；空输出即放行。
# SessionStart 不经过这里，由插件根的 hooks.json 直接转换 secrets.sh 的输出。
# 退出码永远 0；适配失败一律拒绝，闸门静默放行等于没有。
set -u

deny() {  # $1 原因
  jq -nc --arg reason "$1" '{decision: "deny", reason: $reason}' 2>/dev/null \
    || printf '{"decision":"deny","reason":"%s"}\n' '[gox-guard/antigravity] Hook adapter failed. Check jq and the hook scripts before retrying.'
  exit 0
}
adapter_error() {
  deny '[gox-guard/antigravity] Hook adapter failed. Check jq and the hook scripts before retrying.'
}

DIR="$(cd "$(dirname "$0")" && pwd)" || adapter_error
[ -t 0 ] && adapter_error
INPUT="$(cat)" || adapter_error
[ -n "$INPUT" ] || adapter_error

# 转成 secrets.sh 读取的 Claude 形状；缺 jq 时透传原始输入，由原脚本的无 jq 分支判断是否拒绝。
if command -v jq >/dev/null 2>&1; then
  INPUT="$(printf '%s' "$INPUT" | jq -ce '
    (.toolCall.args.Cwd // "") as $dir
    | {
        tool_input: {command: (.toolCall.args.CommandLine // "")},
        cwd: (if $dir == "" then .cwd
              elif ($dir | startswith("/")) then $dir
              else (.cwd // env.PWD) + "/" + $dir end)
      }
  ' 2>/dev/null)" || adapter_error
fi

OUT="$(printf '%s' "$INPUT" | bash "$DIR/secrets.sh" PreToolUse)" || adapter_error
[ -n "$OUT" ] || exit 0

REASON="$(printf '%s' "$OUT" | jq -sre '
  if length == 1 and .[0].hookSpecificOutput.permissionDecision == "deny"
  then .[0].hookSpecificOutput.permissionDecisionReason | strings
  else error("unexpected hook output") end
' 2>/dev/null)" || adapter_error
deny "$REASON"
