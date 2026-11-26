#!/usr/bin/env bats
# GitHub 上的 Go 库加 CI：版本从仓库文件读，每个 workflow 带权限、并发和超时。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
  WF="$WORK/.github/workflows"
}

@test "loads scaffold" {
  require_plugin_run
  skill_loaded scaffold
}

@test "workflows exist and no GitLab pipeline is added" {
  ls "$WF"/*.yml >/dev/null
  [ ! -e "$WORK/.gitlab-ci.yml" ]
}

@test "Go version is read from go.mod, never written into a workflow" {
  grep -rq 'go-version-file: go.mod' "$WF"
  run grep -rnE '^[[:space:]]*go-version:' "$WF"
  [ "$status" -ne 0 ]
}

@test "golangci-lint version is read from .golangci-lint-version" {
  # action 的 version-file 或 make lint 都读同一个文件；写死版本号才算错
  grep -rqE 'version-file: \.golangci-lint-version|make lint' "$WF"
  run grep -rnE '^[[:space:]]*version:[[:space:]]*v?[0-9]' "$WF"
  [ "$status" -ne 0 ]
}

@test "every workflow declares permissions" {
  for f in "$WF"/*.yml; do
    grep -qE '^permissions:' "$f" || { echo "no permissions: $f"; false; }
  done
}

@test "every workflow sets a concurrency group" {
  for f in "$WF"/*.yml; do
    grep -qE '^concurrency:' "$f" || { echo "no concurrency: $f"; false; }
  done
}

@test "every job has a timeout" {
  jobs="$(cat "$WF"/*.yml | grep -cE '^[[:space:]]+runs-on:')"
  timeouts="$(cat "$WF"/*.yml | grep -cE '^[[:space:]]+timeout-minutes:')"
  [ "$jobs" -gt 0 ]
  [ "$timeouts" -ge "$jobs" ]
}

@test "actions are pinned to a major tag" {
  run grep -rhoE 'uses:[[:space:]]*[^[:space:]]+' "$WF"
  [ "$status" -eq 0 ]
  while read -r _ ref; do
    [[ "$ref" =~ @v[0-9]+$ ]] || { echo "not a major tag: $ref"; false; }
  done <<<"$output"
}

@test "checkout is at the major that was current when the case was written (v7)" {
  major="$(grep -rhoE 'actions/checkout@v[0-9]+' "$WF" | head -n 1 | sed 's/.*@v//')"
  [ "$major" -ge 7 ]
}

@test "tests run through make" {
  grep -rq 'make test' "$WF"
}

@test "triggers name the main branch" {
  grep -rqE '^[[:space:]]+- main$|branches:[[:space:]]*\[[[:space:]]*main' "$WF"
}
