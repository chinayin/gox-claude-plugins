#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/session-nudge.sh"
}

@test "outputs valid JSON with hookEventName=SessionStart (no-arg default, backward compatible)" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
}

@test "outputs hookEventName=SubagentStart when invoked with SubagentStart" {
  run bash "$HOOK" SubagentStart
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"'
}

@test "additionalContext mentions the go, frontend, shell and engineering skills (both events)" {
  for ev in SessionStart SubagentStart; do
    run bash "$HOOK" "$ev"
    echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:go"
    echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:frontend"
    echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:shell"
    echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:engineering"
  done
}

@test "additionalContext tells the model to state the skill in subagent briefs" {
  run bash "$HOOK"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -qi "subagent"
}

@test "unknown event name fails open (exit 0, no output)" {
  run bash "$HOOK" BogusEvent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "never exits 2" {
  run bash "$HOOK"
  [ "$status" -ne 2 ]
  run bash "$HOOK" SubagentStart
  [ "$status" -ne 2 ]
}

@test "fail-open when jq is missing (exit 0, no output)" {
  # /bin has bash/cat but no jq, simulating a missing-jq environment
  run env PATH="/bin" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
