#!/usr/bin/env bats
#
# gox-guard 的 hook 注册：SessionStart 做依赖检查，PreToolUse 只挂 Bash 工具并带超时，
# 事件名以参数传给脚本；hooks/ 下的脚本与 hooks.json 的注册一一对应。

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

@test "every hook script under hooks/ is registered in hooks.json and every registered script exists" {
  dir="$BATS_TEST_DIRNAME/../hooks"
  for s in "$dir"/*.sh; do
    grep -q "hooks/$(basename "$s")" "$HOOKS" || { echo "script not registered: $(basename "$s")"; false; }
  done
  for s in $(jq -r '.. | .command? // empty' "$HOOKS" | grep -oE 'hooks/[A-Za-z0-9_-]+\.sh' | sort -u); do
    [ -f "$dir/../$s" ] || { echo "registered script missing: $s"; false; }
  done
}
