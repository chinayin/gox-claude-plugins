#!/usr/bin/env bats
# 用真实 Git 提交图校验扫描范围；扫描器替身仅把含 REVIEW_SECRET 的提交当作发现。

setup() {
  bats_require_minimum_version 1.5.0
  # 完整复制安装包：hooks 通过相对路径找到 lib，不能依赖源仓库的 cwd。
  PLUGIN="$BATS_TEST_TMPDIR/installed plugin"
  cp -R "$BATS_TEST_DIRNAME/.." "$PLUGIN"
  HOOK="$PLUGIN/hooks/secrets.sh"
  CURSOR_HOOK="$PLUGIN/hooks/secrets-cursor.sh"
  REPO="$BATS_TEST_TMPDIR/repo with spaces"
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  SCANNER="$BATS_TEST_TMPDIR/scanner"
  SCAN_LOG="$BATS_TEST_TMPDIR/scan.log"
  git init -q --bare "$REMOTE"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name test
  git -C "$REPO" config user.email test@example.invalid
  printf 'base\n' > "$REPO/fixture"
  git -C "$REPO" add fixture
  git -C "$REPO" commit -qm base
  git -C "$REPO" remote add origin "$REMOTE"
  git -C "$REPO" push -qu origin main
  export SCAN_LOG
  unset GOX_GUARD_SKIP CURSOR_PLUGIN_ROOT CLAUDE_PLUGIN_ROOT
  cat > "$SCANNER" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$PWD" >> "$SCAN_LOG"
for arg in "$@"; do
  case "$arg" in --log-opts=*) range="${arg#--log-opts=}" ;; esac
done
# 故意使用 Git 验证传入范围：只在该范围确实包含测试标记时返回发现。
for commit in $(git rev-list $range); do
  if git grep -q REVIEW_SECRET "$commit" --; then
    printf '[{"RuleID":"fixture","File":"fixture","StartLine":1,"Commit":"%s","Fingerprint":"test"}]\n' "$commit"
    exit 1
  fi
done
exit 0
SH
  chmod +x "$SCANNER"
}

commit_fixture() {
  printf '%s\n' "$1" > "$REPO/fixture"
  git -C "$REPO" add fixture
  git -C "$REPO" commit -qm fixture
}

secret_branch() {
  git -C "$REPO" checkout -qb feature
  commit_fixture REVIEW_SECRET
  git -C "$REPO" checkout -q main
}

check_push() {
  local cmd="$1" cwd="${2:-$REPO}" hook="${3:-$HOOK}" working_dir="${4:-}" input
  input="$(jq -nc \
    --arg cmd "$cmd" --arg cwd "$cwd" --arg wd "$working_dir" \
    '{cwd:$cwd,tool_input:({command:$cmd} + (if $wd == "" then {} else {working_directory:$wd} end))}')" || return 1
  run --separate-stderr env GOX_GUARD_BIN="$SCANNER" bash "$hook" PreToolUse <<<"$input"
  [ "$status" -eq 0 ]
}

assert_denied() {
  [ -n "$output" ]
  jq -e '(.hookSpecificOutput.permissionDecision // .permission) == "deny"' <<<"$output"
}

@test "detection: literal Git executable paths scan pending commits" {
  commit_fixture REVIEW_SECRET
  mkdir -p "$REPO/bin with spaces"
  ln -s "$(command -v git)" "$REPO/bin with spaces/git"
  for hook in "$HOOK" "$CURSOR_HOOK"; do
    for executable in "$(command -v git)" "'$REPO/bin with spaces/git'" "'./bin with spaces/git'"; do
      : > "$SCAN_LOG"
      check_push "$executable push origin main" "$REPO" "$hook"
      assert_denied
      [ -s "$SCAN_LOG" ]
    done
  done
}

@test "detection: a clean push through an absolute Git path is allowed after scanning" {
  commit_fixture clean
  for hook in "$HOOK" "$CURSOR_HOOK"; do
    : > "$SCAN_LOG"
    check_push "'$(command -v git)' push origin main" "$REPO" "$hook"
    if [ "$hook" = "$HOOK" ]; then [ -z "$output" ];
    else jq -e '.permission == "allow"' <<<"$output"; fi
    [ -s "$SCAN_LOG" ]
  done
}

@test "detection: command-like text in arguments and literal heredocs does not trigger scanning" {
  commit_fixture REVIEW_SECRET
  for hook in "$HOOK" "$CURSOR_HOOK"; do
    for command in \
      "rg -n 'git push|PreToolUse' README.md" \
      "printf '%s\\n' 'git push origin main'" \
      "printf 'example: %-20s %% done\\n' 'git push origin main'" \
      'echo git push origin main' \
      "grep -n 'git push origin' README.md" \
      $'cat <<\'DOC\'\ngit push origin main\n$(git push origin main)\nDOC' \
      $'cat <<-"DOC"\n\tgit push origin main\n\tDOC\n'; do
      : > "$SCAN_LOG"
      check_push "$command" "$REPO" "$hook"
      if [ "$hook" = "$HOOK" ]; then [ -z "$output" ];
      else jq -e '.permission == "allow"' <<<"$output"; fi
      [ ! -s "$SCAN_LOG" ]
    done
  done
}

@test "detection: actual pushes after text arguments or inside substitutions remain denied" {
  commit_fixture REVIEW_SECRET
  for hook in "$HOOK" "$CURSOR_HOOK"; do
    for command in \
      "printf '%s' 'git push example' && $(command -v git) push origin main" \
      'printf "%s" "$(git push origin main)"' \
      'printf "%s" "`git push`"' \
      "printf -v 'a[\$(git push)]' '%s' value" \
      "printf -v'a[\$(git push)]' '%s' value" \
      "printf '%n' 'a[\$(git push)]'" \
      "bash -c 'git push origin main'" \
      "eval 'git push origin main'" \
      'env git push origin main' \
      'command git push origin main' \
      "rg --pre 'git push origin main' pattern" \
      "rg --pre='git push origin main' pattern" \
      "rg --hostname-bin='git push origin main' pattern" \
      $'cat <<DOC\n$(git push origin main)\nDOC' \
      $'cat <<\'DOC\'\ngit push example\nDOC\ngit push origin main' \
      $'cat <<\'DOC\'\ntext\nDOC\ngit push origin main\nDOC' \
      $'cat <<\'DOC\' <<\'OTHER\'\ngit push example\nDOC\ngit push origin main\nOTHER'; do
      check_push "$command" "$REPO" "$hook"
      assert_denied
    done
  done
}

@test "scope: quoted git -C scans the target repository from outside it" {
  commit_fixture REVIEW_SECRET
  check_push "git -C '$REPO' push" "$BATS_TEST_TMPDIR"
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: repeated relative -C and a literal cd prefix select the target" {
  commit_fixture REVIEW_SECRET
  for cmd in "git -C '$BATS_TEST_TMPDIR' -C 'repo with spaces' push" "cd '$REPO' && git push"; do
    check_push "$cmd" "$BATS_TEST_TMPDIR"
    assert_denied
    [ -s "$SCAN_LOG" ]
  done
}

@test "scope: cd options are not mistaken for literal directory names" {
  mv "$REPO" "$BATS_TEST_TMPDIR/-P"
  check_push 'cd -P && git push' "$BATS_TEST_TMPDIR"
  assert_denied
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: Cursor working_directory overrides hook cwd including relative paths" {
  commit_fixture REVIEW_SECRET
  for directory in "$REPO" 'repo with spaces'; do
    check_push 'git push' "$BATS_TEST_TMPDIR" "$CURSOR_HOOK" "$directory"
    assert_denied
    [ -s "$SCAN_LOG" ]
  done
}

@test "scope: explicit branch and forced refspec scan a non-current branch" {
  secret_branch
  for cmd in 'git push origin feature' 'git push origin +feature:refs/heads/review'; do
    check_push "$cmd"
    assert_denied
    [ -s "$SCAN_LOG" ]
  done
}

@test "scope: clean explicit branch does not scan unrelated secret commits" {
  secret_branch
  commit_fixture clean
  check_push 'git push origin main'
  [ -z "$output" ]
  [ -s "$SCAN_LOG" ]
}

@test "scope: configured push refspec is used instead of HEAD" {
  secret_branch
  git -C "$REPO" config remote.origin.push feature:refs/heads/review
  check_push 'git push'
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: pushRemote selects that remote's configured source" {
  secret_branch
  git -C "$REPO" remote add publish "$REMOTE"
  git -C "$REPO" config branch.main.pushRemote publish
  git -C "$REPO" config remote.publish.push feature:refs/heads/review
  check_push 'git push'
  assert_denied
}

@test "scope: the sole remote supplies push mappings without an upstream" {
  secret_branch
  git -C "$REPO" remote rename origin publish
  git -C "$REPO" config --unset branch.main.remote
  git -C "$REPO" config --unset branch.main.merge
  git -C "$REPO" config remote.publish.push feature:refs/heads/review
  check_push 'git push'
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: matching and all scan branches beyond the current HEAD" {
  secret_branch
  for cmd in 'git -c push.default=matching push' 'git push --all'; do
    check_push "$cmd"
    assert_denied
  done
}

@test "scope: configured recursive pushes are denied unless explicitly disabled" {
  commit_fixture clean
  for value in on-demand only; do
    git -C "$REPO" config push.recurseSubmodules "$value"
    check_push 'git push'
    assert_denied
    [ ! -e "$SCAN_LOG" ]
  done
  check_push 'git push --recurse-submodules=no'
  [ -z "$output" ]
  [ -s "$SCAN_LOG" ]
}

@test "scope: submodule.recurse defaults cannot enable unscanned submodule pushes" {
  commit_fixture clean
  git -C "$REPO" config submodule.recurse true
  check_push 'git push'
  assert_denied
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: tags include commits that no branch reaches" {
  secret_branch
  git -C "$REPO" tag -a release -m release feature
  git -C "$REPO" branch -D feature >/dev/null
  for cmd in 'git push origin tag release' 'git push origin refs/tags/release' 'git push --tags'; do
    check_push "$cmd"
    assert_denied
    [ -s "$SCAN_LOG" ]
  done
}

@test "scope: mirror includes custom refs outside local branches" {
  secret_branch
  git -C "$REPO" update-ref refs/review/pending feature
  git -C "$REPO" branch -D feature >/dev/null
  check_push 'git push --mirror'
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: quoted wildcard refspec includes its matching branch" {
  secret_branch
  check_push "git push origin 'refs/heads/feat*:refs/heads/feat*'"
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: pure deletions do not scan unrelated pending secrets" {
  commit_fixture REVIEW_SECRET
  for cmd in 'git push origin :feature' 'git push origin --delete feature' 'git push origin --delete tag'; do
    check_push "$cmd"
    [ -z "$output" ]
    [ ! -e "$SCAN_LOG" ]
  done
}

@test "scope: a tag deletion cannot hide a later push in the same shell command" {
  secret_branch
  check_push 'git push --delete origin tag && git push origin feature'
  assert_denied
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: multiline commands cannot hide a later push after a deletion" {
  secret_branch
  check_push $'git push origin --delete old\ngit push origin feature'
  assert_denied
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: attached -C with a quoted directory still triggers scanning" {
  commit_fixture REVIEW_SECRET
  check_push "git -C'$REPO' push" "$BATS_TEST_TMPDIR"
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: configured mirror includes custom refs" {
  secret_branch
  git -C "$REPO" update-ref refs/review/pending feature
  git -C "$REPO" branch -D feature >/dev/null
  git -C "$REPO" config remote.origin.mirror true
  check_push 'git push'
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "scope: commit-and-push chains are denied before a stale clean scan" {
  check_push 'git add . && git commit -m next && git push'
  assert_denied
  [[ "$output" == *"separate"* ]]
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: shell expansions are denied without executing them" {
  marker="$BATS_TEST_TMPDIR/must-not-exist"
  check_push "git -C \"\$(touch '$marker')\" push"
  assert_denied
  [ ! -e "$marker" ]
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: unknown Git options and invalid sources do not silently allow" {
  for cmd in "git --git-dir='$REPO/.git' push" 'git push origin no-such-branch'; do
    check_push "$cmd"
    assert_denied
    [ ! -e "$SCAN_LOG" ]
  done
}

@test "scope: colon-containing revision expressions are not mistaken for deletions" {
  secret_branch
  check_push "git push origin ':/fixture:refs/heads/review'"
  assert_denied
  [ ! -e "$SCAN_LOG" ]
}

@test "scope: failed directory resolution does not fall back to a clean cwd" {
  check_push "git -C '$BATS_TEST_TMPDIR/missing' push"
  assert_denied
  [ ! -e "$SCAN_LOG" ]
}

@test "installed Claude and Codex hook command resolves helper files outside the repo cwd" {
  secret_branch
  command="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$PLUGIN/hooks/hooks.json")"
  input="$(jq -nc --arg cwd "$BATS_TEST_TMPDIR" --arg cmd "git -C '$REPO' push origin feature" '{cwd:$cwd,tool_input:{command:$cmd}}')"
  cd "$BATS_TEST_TMPDIR"
  # 执行受信任的配置入口，不执行 payload 中的待拦截命令。
  run env GOX_GUARD_BIN="$SCANNER" CLAUDE_PLUGIN_ROOT="$PLUGIN" bash -c "$command" <<<"$input"
  [ "$status" -eq 0 ]
  assert_denied
  [ -s "$SCAN_LOG" ]
}

@test "installed Cursor hook command scans the requested non-HEAD ref and allows a clean ref" {
  secret_branch
  commit_fixture clean
  command="$(jq -r '.hooks.preToolUse[0].command' "$PLUGIN/hooks/hooks-cursor.json")"
  cd "$PLUGIN"
  for ref in feature main; do
    input="$(jq -nc --arg cwd "$BATS_TEST_TMPDIR" --arg wd "$REPO" --arg cmd "git push origin $ref" '{cwd:$cwd,tool_input:{command:$cmd,working_directory:$wd}}')"
    run env GOX_GUARD_BIN="$SCANNER" bash -c "$command" <<<"$input"
    [ "$status" -eq 0 ]
    if [ "$ref" = feature ]; then assert_denied
    else jq -e '.permission == "allow"' <<<"$output"; fi
    [ -s "$SCAN_LOG" ]
  done
}

@test "installed shared and Cursor hooks deny when the packaged scope helper is missing" {
  commit_fixture clean
  rm "$PLUGIN/lib/push-scope.sh"
  for hook in "$HOOK" "$CURSOR_HOOK"; do
    check_push 'git push' "$REPO" "$hook"
    assert_denied
    [ ! -e "$SCAN_LOG" ]
  done
}
