#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../src/lib/items.sh"
  mkdir "$BATS_TEST_TMPDIR/items"
  touch "$BATS_TEST_TMPDIR/items/a" "$BATS_TEST_TMPDIR/items/b" "$BATS_TEST_TMPDIR/items/c"
}

@test "items_list honours the limit" {
  run items_list "$BATS_TEST_TMPDIR/items" 2
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "items_list prints nothing for a missing directory" {
  run items_list "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
