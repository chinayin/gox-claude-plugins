#!/usr/bin/env bats
# 只在临时目录替换子脚本，以复现真实扫描器无法触发的协议错误与进程失败。

setup() {
  DIR="$BATS_TEST_TMPDIR/installed plugin"
  mkdir -p "$DIR"
  cp "$BATS_TEST_DIRNAME/../hooks/cursor-secrets.sh" "$DIR/cursor-secrets.sh"
}

@test "Cursor adapter denies instead of swallowing a child process failure" {
  printf '#!/usr/bin/env bash\nexit 3\n' > "$DIR/secrets.sh"
  run bash "$DIR/cursor-secrets.sh" PreToolUse <<<'{"tool_input":{"command":"git push"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.permission == "deny" and (.agent_message | length > 0)'
}

@test "Cursor adapter denies malformed, unexpected or multiple child responses" {
  for response in 'not-json' '{}' '{"hookSpecificOutput":{"permissionDecision":"deny"}}' \
    '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"first"}} {"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"second"}}'; do
    printf '#!/usr/bin/env bash\nprintf "%%s" '\''%s'\''\n' "$response" > "$DIR/secrets.sh"
    run bash "$DIR/cursor-secrets.sh" PreToolUse <<<'{"tool_input":{"command":"git push"}}'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.permission == "deny" and (.agent_message | contains("adapter failed"))'
  done
}

@test "Cursor adapter preserves quotes, backslashes and newlines in both denial messages" {
  reason=$'blocked: "quoted"\\path\nnext line'
  jq -n --arg reason "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' > "$DIR/response.json"
  cat > "$DIR/secrets.sh" <<'EOF'
#!/usr/bin/env bash
cat "$(dirname "$0")/response.json"
EOF
  run bash "$DIR/cursor-secrets.sh" PreToolUse <<<'{"tool_input":{"command":"git push"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg reason "$reason" '.permission == "deny" and .user_message == $reason and .agent_message == $reason'
}
