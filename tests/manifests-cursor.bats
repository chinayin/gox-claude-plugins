#!/usr/bin/env bats
#
# Cursor marketplace wiring. Claude 的清单仍在 .claude-plugin/。
# diagram-design 只留在 Claude marketplace（远程源），不出现在这里。

ROOT="$BATS_TEST_DIRNAME/.."
MKT="$ROOT/.cursor-plugin/marketplace.json"

@test "cursor marketplace.json is valid JSON and names chinayin" {
  run jq -e '.name == "chinayin" and .owner.name == "chinayin"' "$MKT"
  [ "$status" -eq 0 ]
}

@test "cursor marketplace lists exactly the three local plugins" {
  run jq -er '.plugins | map(.name) | sort | join(",")' "$MKT"
  [ "$output" = "gox-code-rules,gox-guard,token-thrift" ]
}

@test "each cursor entry source is plugins/<name> and versions match the Claude manifest" {
  [ -f "$MKT" ]
  names="$(jq -er '.plugins[].name' "$MKT")"
  [ -n "$names" ]
  for name in $names; do
    run jq -er --arg n "$name" '.plugins[] | select(.name==$n) | .source' "$MKT"
    [ "$output" = "plugins/$name" ] || { echo "bad source for $name: $output"; false; }
    pj="$ROOT/plugins/$name/.cursor-plugin/plugin.json"
    claude="$ROOT/plugins/$name/.claude-plugin/plugin.json"
    [ -f "$pj" ] || { echo "missing cursor plugin.json: $name"; false; }
    run jq -e --arg n "$name" '.name == $n' "$pj"
    [ "$status" -eq 0 ] || { echo "cursor plugin name != $name"; false; }
    cv="$(jq -r '.version' "$claude")"
    uv="$(jq -r '.version' "$pj")"
    [ "$cv" = "$uv" ] || { echo "version mismatch $name claude=$cv cursor=$uv"; false; }
  done
}

@test "hook plugins point at hooks-cursor.json and token-thrift declares skills plus agents" {
  for name in gox-code-rules gox-guard; do
    pj="$ROOT/plugins/$name/.cursor-plugin/plugin.json"
    run jq -er '.hooks' "$pj"
    [ "$output" = "./hooks/hooks-cursor.json" ]
    [ -f "$ROOT/plugins/$name/hooks/hooks-cursor.json" ]
  done
  pj="$ROOT/plugins/token-thrift/.cursor-plugin/plugin.json"
  run jq -er '.skills' "$pj"
  [ "$output" = "./skills/" ]
  run jq -er '.agents' "$pj"
  [ "$output" = "./agents-cursor/" ]
  run jq -e 'has("hooks") | not' "$pj"
  [ "$status" -eq 0 ]
}
