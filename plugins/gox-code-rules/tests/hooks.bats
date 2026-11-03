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

@test "hooks-cursor.json registers sessionStart and subagentStart with the Claude event args" {
  cursor="$BATS_TEST_DIRNAME/../hooks/hooks-cursor.json"
  run jq -e . "$cursor"
  [ "$status" -eq 0 ]
  run jq -er '.hooks.sessionStart[0].command' "$cursor"
  [ "$output" = "bash ./hooks/session-nudge.sh SessionStart" ]
  run jq -er '.hooks.subagentStart[0].command' "$cursor"
  [ "$output" = "bash ./hooks/session-nudge.sh SubagentStart" ]
  run jq -er '.hooks | keys | sort | join(",")' "$cursor"
  [ "$output" = "sessionStart,subagentStart" ]
}
