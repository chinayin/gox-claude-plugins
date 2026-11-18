#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  CLI="$BATS_TEST_DIRNAME/../pilot"
  export ITEMS_DIR="$BATS_TEST_TMPDIR/items"
  mkdir "$ITEMS_DIR"
  echo "hello" >"$ITEMS_DIR/a"
}

@test "--help exits 0" {
  run -0 "$CLI" --help
}

@test "unknown option exits 1 with the message on stderr" {
  run --separate-stderr "$CLI" list --nope
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "list --json emits pure JSON" {
  run --separate-stderr "$CLI" list --json
  [ "$status" -eq 0 ]
  jq -e . <<<"$output" >/dev/null
}

@test "remove refuses without --force" {
  run -1 "$CLI" remove a
  [ -f "$ITEMS_DIR/a" ]
}

@test "remove --dry-run changes nothing" {
  run -0 "$CLI" remove a --dry-run
  [ -f "$ITEMS_DIR/a" ]
}
