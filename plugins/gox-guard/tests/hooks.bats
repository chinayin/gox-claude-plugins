#!/usr/bin/env bats
#
# gox-guard 的 hook 注册：SessionStart 做依赖检查，PreToolUse 只挂 Bash 工具并带超时，
# 事件名以参数传给脚本；Claude 与 Cursor 的入口分别注册。

HOOKS="$BATS_TEST_DIRNAME/../hooks/hooks.json"

@test "hooks.json is valid JSON" {
  run jq -e . "$HOOKS"
  [ "$status" -eq 0 ]
}

@test "SessionStart runs secrets.sh with the SessionStart event arg" {
  run jq -er '.hooks.SessionStart[0].hooks[0].command' "$HOOKS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secrets.sh\" SessionStart" ]]
}

@test "PreToolUse is scoped to the Bash tool, runs secrets.sh with the PreToolUse arg, and has a timeout" {
  run jq -er '.hooks.PreToolUse[0].matcher' "$HOOKS"
  [ "$output" = "Bash" ]
  run jq -er '.hooks.PreToolUse[0].hooks[0].command' "$HOOKS"
  [[ "$output" == *"secrets.sh\" PreToolUse" ]]
  run jq -e '.hooks.PreToolUse[0].hooks[0].timeout >= 30' "$HOOKS"
  [ "$status" -eq 0 ]
}

@test "no other events are registered (gates only act on tool calls; SessionStart is the dependency check)" {
  run jq -er '.hooks | keys | sort | join(",")' "$HOOKS"
  [ "$output" = "PreToolUse,SessionStart" ]
}

@test "every hook script is registered in a platform config and every registered script exists" {
  dir="$BATS_TEST_DIRNAME/../hooks"
  cursor="$dir/hooks-cursor.json"
  for s in "$dir"/*.sh; do
    grep -q "hooks/$(basename "$s")" "$HOOKS" "$cursor" || { echo "script not registered: $(basename "$s")"; false; }
  done
  for s in $(jq -r '.. | .command? // empty' "$HOOKS" "$cursor" | grep -oE 'hooks/[A-Za-z0-9_-]+\.sh' | sort -u); do
    [ -f "$dir/../$s" ] || { echo "registered script missing: $s"; false; }
  done
}

@test "hooks-cursor.json scopes preToolUse to Shell and keeps the PreToolUse arg plus a timeout" {
  cursor="$BATS_TEST_DIRNAME/../hooks/hooks-cursor.json"
  run jq -e . "$cursor"
  [ "$status" -eq 0 ]
  run jq -er '.hooks.sessionStart[0].command' "$cursor"
  [ "$output" = "bash ./hooks/cursor-secrets.sh SessionStart" ]
  run jq -er '.hooks.preToolUse[0].matcher' "$cursor"
  [ "$output" = "Shell" ]
  run jq -er '.hooks.preToolUse[0].command' "$cursor"
  [ "$output" = "bash ./hooks/cursor-secrets.sh PreToolUse" ]
  run jq -e '.hooks.preToolUse[0].timeout >= 30 and .hooks.preToolUse[0].failClosed == true' "$cursor"
  [ "$status" -eq 0 ]
  run jq -er '.hooks | keys | sort | join(",")' "$cursor"
  [ "$output" = "preToolUse,sessionStart" ]
}
