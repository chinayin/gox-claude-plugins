#!/usr/bin/env bats

@test "模板含 extraKnownMarketplaces 指向 chinayin 源" {
  run jq -e '.extraKnownMarketplaces.chinayin.source.repo == "chinayin/gox-claude-plugins"' templates/project-settings.json
  [ "$status" -eq 0 ]
}

@test "模板 enabledPlugins 开启 gox-code-rules@chinayin" {
  run jq -e '.enabledPlugins | index("gox-code-rules@chinayin") != null' templates/project-settings.json
  [ "$status" -eq 0 ]
}
