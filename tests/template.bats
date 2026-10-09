#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/.."
TPL="$ROOT/templates/project-settings.json"
MKT="$ROOT/.claude-plugin/marketplace.json"

@test "template has extraKnownMarketplaces pointing to the chinayin source" {
  run jq -e '.extraKnownMarketplaces.chinayin.source.repo == "chinayin/gox-claude-plugins"' "$TPL"
  [ "$status" -eq 0 ]
}

@test "template enabledPlugins uses the Claude settings object with boolean values" {
  run jq -e '.enabledPlugins | if type == "object" then all(.[]; type == "boolean") else false end' "$TPL"
  [ "$status" -eq 0 ] || { echo "enabledPlugins must map plugin IDs to booleans"; false; }
}

@test "template enabledPlugins enables every local plugin in the marketplace" {
  for name in $(jq -r '.plugins[] | select(.source|type=="string") | .name' "$MKT"); do
    run jq -e --arg p "$name@chinayin" '.enabledPlugins | if type == "object" then .[$p] == true else false end' "$TPL"
    [ "$status" -eq 0 ] || { echo "template does not enable: $name@chinayin"; false; }
  done
}

@test "third-party (remote) plugins are opt-in: not enabled by the default template" {
  for name in $(jq -r '.plugins[] | select(.source|type=="object") | .name' "$MKT"); do
    run jq -e --arg p "$name@chinayin" '.enabledPlugins | if type == "object" then has($p) | not else false end' "$TPL"
    [ "$status" -eq 0 ] || { echo "template must not enable third-party plugin by default: $name@chinayin"; false; }
  done
}
