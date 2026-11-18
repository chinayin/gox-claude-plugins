#!/usr/bin/env bats
# 已有 bashly 项目里加子命令，同时改一个手写脚本：两套规则各管各的。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
  CLI="$WORK/pilot"
  export ITEMS_DIR="$BATS_TEST_TMPDIR/items"
  mkdir "$ITEMS_DIR"
  touch "$ITEMS_DIR/a" "$ITEMS_DIR/b"
}

@test "a bashly.yml in the project is enough to load bashly" {
  require_plugin_run
  skill_loaded bashly
}

@test "loads shell as well" {
  require_plugin_run
  skill_loaded shell
}

@test "status prints the item count" {
  run --separate-stderr "$CLI" status
  [ "$status" -eq 0 ]
  [[ "$output" == *2* ]]
}

@test "status --json emits pure JSON" {
  run --separate-stderr "$CLI" status --json
  [ "$status" -eq 0 ]
  jq -e . <<<"$output" >/dev/null
}

@test "status reuses the existing --json anchor" {
  [ "$(grep -cE '^[[:space:]]*-[[:space:]]*\*json' "$WORK/src/bashly.yml")" -ge 2 ]
}

@test "command file exists and reads optional flags with a default" {
  [ -f "$WORK/src/status_command.sh" ]
  run unguarded_optional_flags "$WORK/src"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "generated script was regenerated, not hand-edited" {
  artifact_is_current "$WORK"
}

@test "settings.yml still enables strict mode" {
  grep -qE '^strict:[[:space:]]*true' "$WORK/settings.yml"
}

@test "shellcheck is clean on the generated script and the hand-written one" {
  shellcheck "$CLI" "$WORK/scripts/release.sh"
}

@test "bats tests cover status and all pass" {
  # 排除 bats 自带的 $status 变量，只认作为子命令出现的 status
  grep -lqE '[[:space:]]status([[:space:]]|"|$)' "$WORK"/tests/*.bats
  cd "$WORK"
  HOME="$BATS_TEST_TMPDIR" run bats tests/
  [ "$status" -eq 0 ]
}

@test "release.sh keeps the team header" {
  has_header "$WORK/scripts/release.sh"
}

@test "release.sh --dry-run prints the version and writes nothing" {
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr bash "$WORK/scripts/release.sh" 1.2.3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *1.2.3* ]]
  [ ! -e VERSION ]
}

@test "release.sh still writes VERSION without --dry-run" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$WORK/scripts/release.sh" 1.2.3
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "1.2.3" ]
}
