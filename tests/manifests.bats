#!/usr/bin/env bats

@test "marketplace.json is valid and names chinayin + gox-code-rules" {
  run jq -e '.name == "chinayin" and (.plugins | map(.name) | index("gox-code-rules") != null)' .claude-plugin/marketplace.json
  [ "$status" -eq 0 ]
}

@test "marketplace plugin source is the relative path ./plugins/gox-code-rules" {
  run jq -er '.plugins[] | select(.name=="gox-code-rules") | .source' .claude-plugin/marketplace.json
  [ "$status" -eq 0 ]
  [ "$output" = "./plugins/gox-code-rules" ]
}

@test "plugin.json is valid and names gox-code-rules" {
  run jq -e '.name == "gox-code-rules"' plugins/gox-code-rules/.claude-plugin/plugin.json
  [ "$status" -eq 0 ]
}
