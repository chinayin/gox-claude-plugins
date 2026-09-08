#!/usr/bin/env bats
#
# gox-guard 的 hook 注册：SessionStart 做安装检查，PreToolUse 只挂 Bash 工具，
# 事件名以参数传给同一个脚本；PreToolUse 要带超时（扫描是外部进程）。

HOOKS="$BATS_TEST_DIRNAME/../hooks/hooks.json"

@test "hooks.json is valid JSON" {
  run jq -e . "$HOOKS"
  [ "$status" -eq 0 ]
}

@test "SessionStart runs guard.sh with the SessionStart event arg" {
  run jq -er '.hooks.SessionStart[0].hooks[0].command' "$HOOKS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"guard.sh\" SessionStart" ]]
}

@test "PreToolUse is scoped to the Bash tool, runs guard.sh with the PreToolUse arg, and has a timeout" {
  run jq -er '.hooks.PreToolUse[0].matcher' "$HOOKS"
  [ "$output" = "Bash" ]
  run jq -er '.hooks.PreToolUse[0].hooks[0].command' "$HOOKS"
  [[ "$output" == *"guard.sh\" PreToolUse" ]]
  run jq -e '.hooks.PreToolUse[0].hooks[0].timeout >= 30' "$HOOKS"
  [ "$status" -eq 0 ]
}

@test "no other events are registered (the gate is push-only by design)" {
  run jq -er '.hooks | keys | sort | join(",")' "$HOOKS"
  [ "$output" = "PreToolUse,SessionStart" ]
}
