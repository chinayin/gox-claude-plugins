#!/usr/bin/env bats
# GitLab 上的 Go 服务补发版文件：按 scaffold 的模板写，而不是按模型的默认习惯。
bats_require_minimum_version 1.5.0
load ../../helpers

setup() {
  eval_setup
}

@test "loads scaffold" {
  require_plugin_run
  skill_loaded scaffold
}

@test "goreleaser config builds with -trimpath and names the archive by platform" {
  [ -f "$WORK/.goreleaser.yaml" ]
  grep -q -- '-trimpath' "$WORK/.goreleaser.yaml"
  grep -qE 'name_template:.*\.Os.*_.*\.Arch' "$WORK/.goreleaser.yaml"
}

@test "goreleaser injects the three main.* version variables" {
  for v in version commit date; do
    grep -q "main\.$v=" "$WORK/.goreleaser.yaml"
  done
}

@test "goreleaser version is left for the user: the CI image is out of reach in this fixture" {
  # 模板项目不存在，镜像无从查起：不该拿本机或最新版顶替，而是不写并在结果里说明缺这个文件
  [ ! -e "$WORK/.goreleaser-version" ]
  jq -r 'select(.type=="result") | .result' "$TRANSCRIPT" | grep -q 'goreleaser-version'
}

@test "Makefile release target uses the pinned goreleaser in ./bin" {
  grep -qE '^release:' "$WORK/Makefile"
  grep -qE '\./bin/goreleaser|\$\(GORELEASER\)' "$WORK/Makefile"
  grep -q 'goreleaser-version' "$WORK/Makefile"
}

@test "Makefile has a docker target" {
  grep -qE '^docker:' "$WORK/Makefile"
}

@test "clean no longer deletes the pinned tools" {
  # bin/ 作为 rm -rf 的任一参数都算（基线常写成 rm -rf bin/ dist/）
  run grep -nE '^[[:space:]]+@?rm -rf([[:space:]]+[^[:space:]]+)*[[:space:]]+bin/?([[:space:]]|$)' "$WORK/Makefile"
  [ "$status" -ne 0 ]
}

@test "Dockerfile only unpacks the CI artifact and compiles nothing" {
  grep -qE '^ADD .*dist/' "$WORK/Dockerfile"
  run grep -nE 'go build|^FROM .*golang' "$WORK/Dockerfile"
  [ "$status" -ne 0 ]
}

@test "image runs as nonroot and sets no TZ" {
  grep -q 'nonroot' "$WORK/Dockerfile"
  run grep -nE '^ENV[[:space:]]+TZ' "$WORK/Dockerfile"
  [ "$status" -ne 0 ]
}

@test ".dockerignore is an allowlist that lets dist/ through" {
  [ "$(grep -vE '^[[:space:]]*(#|$)' "$WORK/.dockerignore" | head -n 1)" = '**' ]
  grep -qE '^!dist/' "$WORK/.dockerignore"
}

@test "lint config is .golangci.yml with a formatter and the team limits" {
  [ -f "$WORK/.golangci.yml" ]
  [ ! -e "$WORK/.golangci.yaml" ]
  grep -q 'gofmt' "$WORK/.golangci.yml"
  grep -qE 'min-complexity:[[:space:]]*15' "$WORK/.golangci.yml"
  grep -qE 'min-complexity:[[:space:]]*20' "$WORK/.golangci.yml"
}

@test ".gitignore covers dist/ and what CI writes into the work tree" {
  grep -qxE '/?dist/?' "$WORK/.gitignore"
  grep -qxE '/?\.cache/?' "$WORK/.gitignore"
  grep -qxE '/?\.go-build\.json' "$WORK/.gitignore"
}

@test "no GitHub workflow is added to a GitLab repo" {
  [ ! -e "$WORK/.github" ]
}

@test "the pipeline still comes from the shared templates" {
  grep -q "project: 'platform/ci-templates'" "$WORK/.gitlab-ci.yml"
  run grep -nE '^[[:space:]]+script:' "$WORK/.gitlab-ci.yml"
  [ "$status" -ne 0 ]
}
