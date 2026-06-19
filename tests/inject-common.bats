#!/usr/bin/env bats

setup() {
  PLUGIN="$BATS_TEST_DIRNAME/../plugins/gox-code-rules"
  HOOK="$PLUGIN/hooks/inject-common.sh"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN"
  GOREPO="$(mktemp -d)"; touch "$GOREPO/go.mod"
  NONGO="$(mktemp -d)"
}

teardown() { rm -rf "$GOREPO" "$NONGO"; }

@test "Go repo: 输出合法 JSON 且含 common 与 Go 规范" {
  export CLAUDE_PROJECT_DIR="$GOREPO"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "团队通用准则"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "Go 规范"
}

@test "非 Go repo:含 common 不含 Go 规范" {
  export CLAUDE_PROJECT_DIR="$NONGO"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "团队通用准则"
  run bash -c "bash '$HOOK' | jq -er '.hookSpecificOutput.additionalContext' | grep -c 'Go 规范' || true"
  [ "$output" = "0" ]
}

@test "fail-open:rules 目录缺失也 exit 0 无崩溃" {
  export CLAUDE_PLUGIN_ROOT="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$GOREPO"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "绝不 exit 2" {
  export CLAUDE_PROJECT_DIR="$GOREPO"
  run bash "$HOOK"
  [ "$status" -ne 2 ]
}

@test "GOX_RULES_DEBUG 把日志写 stderr 不污染 stdout JSON" {
  export CLAUDE_PROJECT_DIR="$GOREPO" GOX_RULES_DEBUG=1
  run bash -c "bash '$HOOK' 2>/dev/null | jq -e '.hookSpecificOutput'"
  [ "$status" -eq 0 ]
}
