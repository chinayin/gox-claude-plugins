#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../plugins/gox-code-rules/hooks/session-nudge.sh"
}

@test "输出合法 JSON,hookEventName=SessionStart" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
}

@test "additionalContext 提到 go 与 common 技能" {
  run bash "$HOOK"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:go"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:common"
}

@test "绝不 exit 2" {
  run bash "$HOOK"
  [ "$status" -ne 2 ]
}

@test "缺 jq 时 fail-open(exit 0 无输出)" {
  # /bin 有 bash/cat 但无 jq,模拟缺 jq 环境
  run env PATH="/bin" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
