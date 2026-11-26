#!/usr/bin/env bats
#
# gox-code-rules specific: session-nudge 必须同时注册到 SessionStart 与
# SubagentStart（提醒直达每个子代理），且事件名以参数传给脚本。

HOOKS="$BATS_TEST_DIRNAME/../hooks/hooks.json"

@test "hooks.json registers session-nudge on both SessionStart and SubagentStart with matching event arg" {
  run jq -er '.hooks.SessionStart[0].hooks[0].command' "$HOOKS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session-nudge.sh\" SessionStart" ]]
  run jq -er '.hooks.SubagentStart[0].hooks[0].command' "$HOOKS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session-nudge.sh\" SubagentStart" ]]
}

@test "hooks-cursor.json only registers sessionStart because subagentStart cannot inject context" {
  cursor="$BATS_TEST_DIRNAME/../hooks/hooks-cursor.json"
  run jq -e . "$cursor"
  [ "$status" -eq 0 ]
  run jq -er '.hooks.sessionStart[0].command' "$cursor"
  [ "$output" = "bash ./hooks/session-nudge-cursor.sh SessionStart" ]
  run jq -er '.hooks | keys | sort | join(",")' "$cursor"
  [ "$output" = "sessionStart" ]
}

@test "Antigravity hooks.json only registers SessionStart and injects the nudge as a system message" {
  root="$BATS_TEST_DIRNAME/.."
  agy="$root/hooks.json"
  run jq -er '."gox-code-rules" | keys | join(",")' "$agy"
  [ "$output" = "SessionStart" ]
  # agy 以 sh -c 在插件根执行
  cmd="$(jq -er '."gox-code-rules".SessionStart[0].command' "$agy")"
  run bash -c 'cd "$1" && sh -c "$2"' _ "$root" "$cmd"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.injectSteps[0].systemMessage.systemMessage | contains("gox-code-rules:go")'
}
