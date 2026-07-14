#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/.."
TPL="$ROOT/templates/project-settings.json"

@test "template has extraKnownMarketplaces pointing to the chinayin source" {
  run jq -e '.extraKnownMarketplaces.chinayin.source.repo == "chinayin/gox-claude-plugins"' "$TPL"
  [ "$status" -eq 0 ]
}

@test "template enabledPlugins enables gox-code-rules@chinayin and token-thrift@chinayin" {
  run jq -e '(.enabledPlugins | index("gox-code-rules@chinayin") != null) and (.enabledPlugins | index("token-thrift@chinayin") != null)' "$TPL"
  [ "$status" -eq 0 ]
}
