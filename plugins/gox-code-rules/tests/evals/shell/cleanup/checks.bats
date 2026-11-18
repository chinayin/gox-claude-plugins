#!/usr/bin/env bats
# 会删除文件的脚本：要有守卫、退出码约定和自测。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
  SCRIPT="$WORK/scripts/clean-logs.sh"
  LOGS="$BATS_TEST_TMPDIR/logs"
  mkdir "$LOGS"
  touch -t 202001010000 "$LOGS/old.log"
  touch "$LOGS/new.log"
}

# 规范写的是 --force "or similar"，两个常见名字都试
force_delete() {
  bash "$SCRIPT" "$@" --force || bash "$SCRIPT" "$@" --yes
}

@test "loads shell and not bashly" {
  require_plugin_run
  skill_loaded shell
  run skill_loaded bashly
  [ "$status" -ne 0 ]
}

@test "script exists with the team header" {
  [ -f "$SCRIPT" ]
  has_header "$SCRIPT"
}

@test "shellcheck is clean" {
  shellcheck "$SCRIPT"
}

@test "no emoji or color" {
  no_emoji_or_color "$SCRIPT"
}

@test "refuses to delete without an explicit confirmation flag" {
  run bash "$SCRIPT" "$LOGS"
  [ -f "$LOGS/old.log" ]
}

@test "--dry-run exits 0 and deletes nothing" {
  run bash "$SCRIPT" "$LOGS" --dry-run
  [ "$status" -eq 0 ]
  [ -f "$LOGS/old.log" ]
}

@test "deletes only old logs once confirmed" {
  run force_delete "$LOGS"
  [ ! -e "$LOGS/old.log" ]
  [ -f "$LOGS/new.log" ]
}

@test "--days is honoured" {
  run force_delete "$LOGS" --days 99999
  [ -f "$LOGS/old.log" ]
}

@test "unknown option exits 1 with Error: on stderr and nothing on stdout" {
  run --separate-stderr bash "$SCRIPT" "$LOGS" --nope
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Error: "* ]]
}

@test "--help exits 0 on stdout" {
  run --separate-stderr bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "ships a passing test.sh" {
  t="$(find_file test.sh)"
  cd "$(dirname "$t")"
  HOME="$BATS_TEST_TMPDIR" run bash "$t"
  [ "$status" -eq 0 ]
}
