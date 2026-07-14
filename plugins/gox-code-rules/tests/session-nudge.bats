#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/session-nudge.sh"
}

@test "outputs valid JSON with hookEventName=SessionStart" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
}

@test "additionalContext mentions the go, frontend, shell and engineering skills" {
  run bash "$HOOK"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:go"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:frontend"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:shell"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "gox-code-rules:engineering"
}

@test "never exits 2" {
  run bash "$HOOK"
  [ "$status" -ne 2 ]
}

@test "fail-open when jq is missing (exit 0, no output)" {
  # /bin has bash/cat but no jq, simulating a missing-jq environment
  run env PATH="/bin" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
