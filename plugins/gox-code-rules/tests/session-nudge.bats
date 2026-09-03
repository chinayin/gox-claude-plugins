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

@test "SessionStart context names the go, shell and engineering skills and the one-skill rule" {
  run bash "$HOOK" SessionStart
  ctx="$(echo "$output" | jq -er '.hookSpecificOutput.additionalContext')"
  grep -q "gox-code-rules:go" <<<"$ctx"
  grep -q "gox-code-rules:shell" <<<"$ctx"
  grep -q "gox-code-rules:engineering" <<<"$ctx"
  grep -q "usually exactly one" <<<"$ctx"
  grep -q "not for a one-file edit" <<<"$ctx"
  grep -q "do not re-invoke" <<<"$ctx"
}

@test "SessionStart context tells the model to put the rules in subagent briefs" {
  run bash "$HOOK"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -qi "subagent"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "in its brief"
}

@test "SubagentStart context is the short brief-first variant (go + shell, engineering discouraged)" {
  run bash "$HOOK" SubagentStart
  ctx="$(echo "$output" | jq -er '.hookSpecificOutput.additionalContext')"
  grep -q "Your brief should already state" <<<"$ctx"
  grep -q "only if the brief names none" <<<"$ctx"
  grep -q "gox-code-rules:go" <<<"$ctx"
  grep -q "gox-code-rules:shell" <<<"$ctx"
  grep -q "Do not invoke \`gox-code-rules:engineering\`" <<<"$ctx"
  # 子代理版必须明显短于主会话版
  run bash "$HOOK" SessionStart
  main_len=$(echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | wc -c)
  [ "${#ctx}" -lt $((main_len / 2)) ]
}

@test "additionalContext carries the no-Skill-tool fallback line (both events)" {
  for ev in SessionStart SubagentStart; do
    run bash "$HOOK" "$ev"
    echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "Skill tool is unavailable"
  done
}

@test "SubagentStart skips injection for cheap-reader (exit 0, no output)" {
  run bash "$HOOK" SubagentStart <<<'{"agent_type":"cheap-reader"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SubagentStart still injects for other agents, bad JSON and empty stdin (fail-open)" {
  run bash "$HOOK" SubagentStart <<<'{"agent_type":"Explore"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"'
  run bash "$HOOK" SubagentStart <<<'not-json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"'
  run bash "$HOOK" SubagentStart </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart"'
}

@test "SessionStart ignores stdin (agent_type must not suppress it)" {
  run bash "$HOOK" SessionStart <<<'{"agent_type":"cheap-reader"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
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
