#!/usr/bin/env bats
#
# Antigravity（agy）按插件子目录 URL 安装，读 .antigravity-plugin/plugin.json 与插件根的 hooks.json。
# token-thrift 的代理按 Claude 模型分档，不提供 agy 清单。

ROOT="$BATS_TEST_DIRNAME/.."

@test "gox-code-rules and gox-guard ship agy manifests matching the Claude name and version" {
  for name in gox-code-rules gox-guard; do
    pj="$ROOT/plugins/$name/.antigravity-plugin/plugin.json"
    claude="$ROOT/plugins/$name/.claude-plugin/plugin.json"
    [ -f "$pj" ] || { echo "missing agy plugin.json: $name"; false; }
    run jq -e --slurpfile c "$claude" '.name == $c[0].name and .version == $c[0].version' "$pj"
    [ "$status" -eq 0 ] || { echo "name/version mismatch: $name"; false; }
    [ -f "$ROOT/plugins/$name/hooks.json" ] || { echo "missing agy hooks.json: $name"; false; }
  done
  [ ! -e "$ROOT/plugins/token-thrift/.antigravity-plugin" ]
}

@test "agy plugin validate accepts both plugins" {
  command -v agy >/dev/null 2>&1 || skip "agy not installed"
  for name in gox-code-rules gox-guard; do
    run agy plugin validate "$ROOT/plugins/$name"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
}
