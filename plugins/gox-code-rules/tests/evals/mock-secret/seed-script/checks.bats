#!/usr/bin/env bats
# 脚本里写死的假凭证：同时会加载 shell 技能，看 mock- 约定是否仍被遵守。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
  SCRIPT="$WORK/scripts/seed-dev.sh"
}

@test "the script holds literal credential values" {
  [ -f "$SCRIPT" ]
  [ -n "$(secret_literals "$SCRIPT")" ]
}

@test "every literal credential starts with mock-" {
  run grep -v '^mock-' <<<"$(secret_literals "$SCRIPT")"
  [ "$status" -ne 0 ] || { echo "not mock-: $output"; false; }
}

@test "the push gate's default scan reports nothing" {
  gate_scan_is_clean
}
