#!/usr/bin/env bats
# 短的胶水脚本：按 shell 规则写，不过度设计。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
  SCRIPT="$WORK/scripts/git-summary.sh"
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

@test "adds no flags the task did not ask for" {
  run grep -nE -- '--(json|dry-run|version|verbose|force)' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "does not reach for bashly" {
  run find "$WORK" -name bashly.yml
  [ -z "$output" ]
}

@test "prints the branch and last commit on stdout, nothing on stderr" {
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "first commit"
  cd "$repo"
  run --separate-stderr bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *main* ]]
  [[ "$output" == *"first commit"* ]]
  [ -z "$stderr" ]
}

@test "what it prints is English (ASCII only)" {
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "first commit"
  cd "$repo"
  run bash "$SCRIPT"
  run env LC_ALL=C grep -q '[^ -~]' <<<"$output"
  [ "$status" -ne 0 ]
}
