#!/usr/bin/env bats
#
# Cross-plugin wiring, generic: every plugins/*/ dir <-> its marketplace entry
# <-> its own plugin.json. Loops over all plugins, so new plugins are covered
# automatically — no per-plugin edits needed here.
#
# 两类条目：本仓插件（source 是 "./plugins/<name>" 字符串）与第三方引用（source 是
# 对象，指向外部 git 仓库，跟随上游默认分支）。第三方引用必须登记在 docs/THIRD_PARTY.md。

ROOT="$BATS_TEST_DIRNAME/.."
MKT="$ROOT/.claude-plugin/marketplace.json"
REG="$ROOT/docs/THIRD_PARTY.md"

local_names()  { jq -r '.plugins[] | select(.source|type=="string") | .name' "$MKT"; }
remote_names() { jq -r '.plugins[] | select(.source|type=="object") | .name' "$MKT"; }

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

@test "every local marketplace entry has a matching dir + plugin.json with the same name" {
  for name in $(local_names); do
    pj="$ROOT/plugins/$name/.claude-plugin/plugin.json"
    [ -f "$pj" ] || { echo "missing plugin.json for marketplace entry: $name"; false; }
    run jq -e --arg n "$name" '.name == $n' "$pj"
    [ "$status" -eq 0 ] || { echo "plugin.json name != marketplace name: $name"; false; }
  done
}

@test "every remote (third-party) entry is a github/git-subdir source with a repo/url" {
  for name in $(remote_names); do
    run jq -er --arg n "$name" '.plugins[] | select(.name==$n) | .source.source' "$MKT"
    [ "$status" -eq 0 ] || { echo "remote entry without source.source: $name"; false; }
    case "$output" in
      github)     run jq -er --arg n "$name" '.plugins[] | select(.name==$n) | .source.repo' "$MKT" ;;
      git-subdir) run jq -er --arg n "$name" '.plugins[] | select(.name==$n) | .source.url' "$MKT" ;;
      *) echo "unsupported remote source for $name: $output"; false ;;
    esac
    [ "$status" -eq 0 ] || { echo "remote entry without repo/url: $name"; false; }
  done
}

@test "every remote (third-party) entry is registered in docs/THIRD_PARTY.md" {
  [ -z "$(remote_names)" ] && return 0
  [ -f "$REG" ] || { echo "missing registry: docs/THIRD_PARTY.md"; false; }
  for name in $(remote_names); do
    grep -q "\`$name\`" "$REG" || { echo "not registered in docs/THIRD_PARTY.md: $name"; false; }
  done
}
