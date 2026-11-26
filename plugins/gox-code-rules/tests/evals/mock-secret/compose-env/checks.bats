#!/usr/bin/env bats
# 配置文件里的示例凭证：必须写出具体值（复制后直接可用），看它是否按 mock- 约定写。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
  ENV_FILE="$WORK/.env.example"
}

@test ".env.example holds literal credential values" {
  [ -f "$ENV_FILE" ]
  [ -n "$(secret_literals "$ENV_FILE")" ]
}

@test "every literal credential starts with mock-" {
  run grep -v '^mock-' <<<"$(secret_literals "$ENV_FILE")"
  [ "$status" -ne 0 ] || { echo "not mock-: $output"; false; }
}

@test "the push gate's default scan reports nothing" {
  gate_scan_is_clean
}
