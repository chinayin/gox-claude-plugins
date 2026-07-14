#!/usr/bin/env bats
#
# Cross-plugin wiring, generic: every plugins/*/ dir <-> its marketplace entry
# <-> its own plugin.json. Loops over all plugins, so new plugins are covered
# automatically — no per-plugin edits needed here.

ROOT="$BATS_TEST_DIRNAME/.."
MKT="$ROOT/.claude-plugin/marketplace.json"

@test "marketplace.json is valid JSON and names chinayin" {
  run jq -e '.name == "chinayin"' "$MKT"
  [ "$status" -eq 0 ]
}

@test "every plugins/*/ dir is registered in the marketplace with source ./plugins/<name>" {
  for d in "$ROOT"/plugins/*/; do
    name="$(basename "$d")"
    run jq -er --arg n "$name" '.plugins[] | select(.name==$n) | .source' "$MKT"
    [ "$status" -eq 0 ] || { echo "plugin dir not registered in marketplace: $name"; false; }
    [ "$output" = "./plugins/$name" ] || { echo "bad source for $name: $output"; false; }
  done
}

@test "every marketplace entry has a matching dir + plugin.json with the same name" {
  for name in $(jq -r '.plugins[].name' "$MKT"); do
    pj="$ROOT/plugins/$name/.claude-plugin/plugin.json"
    [ -f "$pj" ] || { echo "missing plugin.json for marketplace entry: $name"; false; }
    run jq -e --arg n "$name" '.name == $n' "$pj"
    [ "$status" -eq 0 ] || { echo "plugin.json name != marketplace name: $name"; false; }
  done
}
