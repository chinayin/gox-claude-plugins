#!/usr/bin/env bash
# SessionStart hook: 注入团队规范(MVP)。fail-open,绝不 exit 2。
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

dbg() { [ -n "${GOX_RULES_DEBUG:-}" ] && echo "gox: $*" >&2 || true; }

# 缺 jq → fail-open
if ! command -v jq >/dev/null 2>&1; then
  dbg "jq 缺失,fail-open"
  exit 0
fi

context=""
append_file() {
  [ -f "$1" ] || { dbg "跳过(不存在): $1"; return; }
  context+="$(cat "$1")"$'\n\n'
  dbg "已纳入: $1"
}

# common:全部
shopt -s nullglob
for f in "$PLUGIN_ROOT"/rules/common/*.md; do append_file "$f"; done
shopt -u nullglob

# Go:仅当 repo 有 go.mod
if [ -f "$PROJECT_DIR/go.mod" ]; then
  append_file "$PLUGIN_ROOT/rules/go/rules.md"
else
  dbg "无 go.mod,跳过 Go 规范"
fi

# 无内容 → 静默 exit 0
if [ -z "${context//[$'\n\t ']/}" ]; then
  dbg "无规则可注入"
  exit 0
fi

prefix=$'[gox-code-rules] 以下为团队规范,请在本会话中遵循:\n\n'
jq -n --arg ctx "${prefix}${context}" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
  || { dbg "jq 构造失败,fail-open"; exit 0; }
exit 0
