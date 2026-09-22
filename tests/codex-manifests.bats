#!/usr/bin/env bats

@test "Codex marketplace resolves shared plugins with matching platform identities" {
  root="$BATS_TEST_DIRNAME/.."
  while IFS=$'\t' read -r name source; do
    plugin="$root/$source"
    [ -d "$plugin" ]
    [ "$(jq -r .name "$plugin/.codex-plugin/plugin.json")" = "$name" ]
    [ "$(jq -r .name "$plugin/.claude-plugin/plugin.json")" = "$name" ]
    [ "$(jq -r .version "$plugin/.codex-plugin/plugin.json")" = "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" ]
    # Both runtimes discover the same hooks, without a second configuration.
    jq -e 'has("hooks") | not' "$plugin/.codex-plugin/plugin.json"
    [ -f "$plugin/hooks/hooks.json" ]
  done < <(jq -r '.plugins[] | [.name, .source.path] | @tsv' "$root/.agents/plugins/marketplace.json")
  jq -e '.plugins | length == 2' "$root/.agents/plugins/marketplace.json"
}
