#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/session-nudge.sh"
  CURSOR_HOOK="$BATS_TEST_DIRNAME/../hooks/cursor-session-nudge.sh"
  # 协议由入口决定；默认清空变量，另测两种变量共存的情况。
  unset CURSOR_PLUGIN_ROOT
}

@test "every skill named by either nudge exists in the installed plugin" {
  for ev in SessionStart SubagentStart; do
    run bash "$HOOK" "$ev"
    [ "$status" -eq 0 ]
    ctx="$(echo "$output" | jq -er '.hookSpecificOutput.additionalContext')"
    for name in $(grep -oE 'gox-code-rules:[a-z-]+' <<<"$ctx" | sort -u); do
      [ -f "$BATS_TEST_DIRNAME/../skills/${name#gox-code-rules:}/SKILL.md" ] \
        || { echo "unavailable skill in $ev: $name"; false; }
    done
  done
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

@test "SessionStart context names the go, shell, skill and engineering skills and the one-skill rule" {
  run bash "$HOOK" SessionStart
  ctx="$(echo "$output" | jq -er '.hookSpecificOutput.additionalContext')"
  grep -q "gox-code-rules:go" <<<"$ctx"
  grep -q "gox-code-rules:shell" <<<"$ctx"
  grep -q "gox-code-rules:skill\`" <<<"$ctx"
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
  grep -q "gox-code-rules:skill\`" <<<"$ctx"
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

@test "base nudge keeps Claude output even when both plugin root variables are set" {
  for event in SessionStart SubagentStart; do
    run env CURSOR_PLUGIN_ROOT=/cursor CLAUDE_PLUGIN_ROOT=/claude bash "$HOOK" "$event"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg event "$event" '.hookSpecificOutput.hookEventName == $event and (has("additional_context") | not)'
  done
}

@test "CLAUDE_PLUGIN_ROOT alone keeps the Claude hookSpecificOutput shape" {
  run env CLAUDE_PLUGIN_ROOT=/plugin bash "$HOOK" SessionStart
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  echo "$output" | jq -e 'has("additional_context") | not'
}

@test "Claude SubagentStart still skips cheap-reader with Cursor environment inherited" {
  run env CURSOR_PLUGIN_ROOT=/plugin bash "$HOOK" SubagentStart <<<'{"agent_type":"cheap-reader"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Cursor adapter emits only additional_context with or without plugin root variables" {
  for root in '' /cursor; do
    run env CURSOR_PLUGIN_ROOT="$root" CLAUDE_PLUGIN_ROOT=/claude bash "$CURSOR_HOOK" SessionStart <<<'{"subagent_type":"cheap-reader"}'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '(.additional_context | contains("gox-code-rules:go")) and (has("hookSpecificOutput") | not)'
  done
}

@test "Cursor adapter stays silent for unsupported events or missing jq" {
  run bash "$CURSOR_HOOK" BogusEvent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  for event in SessionStart SubagentStart; do
    run env PATH=/bin bash "$CURSOR_HOOK" "$event"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "Cursor subagentStart emits the brief-first reminder as additional_context" {
  run env CURSOR_PLUGIN_ROOT=/cursor CLAUDE_PLUGIN_ROOT=/claude bash "$CURSOR_HOOK" SubagentStart <<<'{"subagent_type":"careful-writer"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.additional_context | contains("Your brief should already state")) and (has("hookSpecificOutput") | not)'
}

@test "Cursor subagentStart skips cheap-reader using native or Claude input fields" {
  for input in '{"subagent_type":"cheap-reader"}' '{"agent_type":"cheap-reader"}'; do
    run bash "$CURSOR_HOOK" SubagentStart <<<"$input"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "Cursor subagentStart still emits a reminder for invalid or empty input" {
  for input in 'not-json' ''; do
    run bash "$CURSOR_HOOK" SubagentStart <<<"$input"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.additional_context | contains("Your brief should already state")'
  done
}
