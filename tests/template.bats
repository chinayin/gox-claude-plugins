#!/usr/bin/env bats

@test "template has extraKnownMarketplaces pointing to the chinayin source" {
  run jq -e '.extraKnownMarketplaces.chinayin.source.repo == "chinayin/gox-claude-plugins"' templates/project-settings.json
  [ "$status" -eq 0 ]
}

@test "template enabledPlugins enables gox-code-rules@chinayin" {
  run jq -e '.enabledPlugins | index("gox-code-rules@chinayin") != null' templates/project-settings.json
  [ "$status" -eq 0 ]
}
