#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/.."
TPL="$ROOT/templates/project-settings.json"

@test "template has extraKnownMarketplaces pointing to the chinayin source" {
  run jq -e '.extraKnownMarketplaces.chinayin.source.repo == "chinayin/gox-claude-plugins"' "$TPL"
  [ "$status" -eq 0 ]
}

@test "template enabledPlugins enables every plugin in the marketplace" {
  for name in $(jq -r '.plugins[].name' "$ROOT/.claude-plugin/marketplace.json"); do
    run jq -e --arg p "$name@chinayin" '.enabledPlugins | index($p) != null' "$TPL"
    [ "$status" -eq 0 ] || { echo "template does not enable: $name@chinayin"; false; }
  done
}
