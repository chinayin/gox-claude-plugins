#!/usr/bin/env bats
# 只在临时目录替换 secrets.sh，复现真实扫描器无法触发的协议错误与进程失败。

setup() {
  DIR="$BATS_TEST_TMPDIR/installed plugin"
  mkdir -p "$DIR"
  cp "$BATS_TEST_DIRNAME/../hooks/secrets-antigravity.sh" "$DIR/secrets-antigravity.sh"
  INPUT='{"toolCall":{"name":"run_command","args":{"CommandLine":"git push"}},"cwd":"/tmp"}'
}

@test "Antigravity adapter denies instead of swallowing a child process failure" {
  printf '#!/usr/bin/env bash\nexit 3\n' > "$DIR/secrets.sh"
  run bash "$DIR/secrets-antigravity.sh" <<<"$INPUT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "deny" and (.reason | contains("adapter failed"))'
}

@test "Antigravity adapter denies malformed, unexpected or multiple child responses" {
  for response in 'not-json' '{}' '{"hookSpecificOutput":{"permissionDecision":"deny"}}' \
    '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"first"}} {"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"second"}}'; do
    printf '#!/usr/bin/env bash\nprintf "%%s" '\''%s'\''\n' "$response" > "$DIR/secrets.sh"
    run bash "$DIR/secrets-antigravity.sh" <<<"$INPUT"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "deny" and (.reason | contains("adapter failed"))'
  done
}

@test "Antigravity adapter denies empty or malformed input" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$DIR/secrets.sh"
  for input in '' 'not-json'; do
    run bash "$DIR/secrets-antigravity.sh" <<<"$input"
    [ "$status" -eq 0 ]
    jq -e '.decision == "deny"' <<<"$output"
  done
}

@test "Antigravity adapter passes the command and Cwd to secrets.sh in Claude shape" {
  printf '#!/usr/bin/env bash\ncat > "$(dirname "$0")/seen.json"\n' > "$DIR/secrets.sh"
  run bash "$DIR/secrets-antigravity.sh" <<<'{"toolCall":{"args":{"CommandLine":"git push","Cwd":"/work/repo"}},"cwd":"/work"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  jq -e '. == {tool_input: {command: "git push"}, cwd: "/work/repo"}' "$DIR/seen.json"
}
