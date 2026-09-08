#!/usr/bin/env bats
#
# gox-guard 的确定性行为：什么时候扫、扫什么区间、拦下时说什么、缺工具怎么办。
# 用 PATH 上的 stub betterleaks 模拟三种结果（干净 / 有发现 / 未安装），真实二进制的
# 行为（flag、报告字段）另由 tests/real-betterleaks.bats 在本机装了 betterleaks 时覆盖。
# 所有 git 操作只发生在 $BATS_TEST_TMPDIR 下的临时仓库里，不碰真实项目。

HOOK="$BATS_TEST_DIRNAME/../hooks/guard.sh"

setup() {
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  # 记录 stub 被调用的次数与参数，供断言"没调"/"调了什么"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  : > "$STUB_LOG"

  # 一个有远端、有一次已推送提交的临时仓库；测试按需再加"领先远端"的提交
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$REMOTE"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  echo base > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm base
  git -C "$REPO" remote add origin "$REMOTE"
  git -C "$REPO" push -q -u origin main
}

# stub_betterleaks <exit-code> [json-report]
# 生成一个假 betterleaks：记录参数，按要求退出；给了报告就打到 stdout（模拟 -r -）
stub_betterleaks() {
  local code="$1" report="${2:-}"
  cat > "$STUB_DIR/betterleaks" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$STUB_LOG"
[ -n '$report' ] && printf '%s\n' '$report'
exit $code
EOF
  chmod +x "$STUB_DIR/betterleaks"
}

# 一次"领先远端"的提交，让待推送区间非空
add_ahead_commit() {
  echo "x=1" > "$REPO/config.txt"
  git -C "$REPO" add config.txt
  git -C "$REPO" commit -qm ahead
}

# run_pre <command> — 以 PreToolUse 的 stdin 形状调用 hook
run_pre() {
  local cmd="$1"
  run env PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" bash "$HOOK" PreToolUse <<EOF
{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"$REPO","tool_input":{"command":$(jq -Rn --arg c "$cmd" '$c')}}
EOF
}

FINDING='[{"RuleID":"aws-access-key","Description":"AWS Access Key","File":"config.txt","StartLine":3,"Commit":"0123456789abcdef","Fingerprint":"0123456789abcdef:config.txt:aws-access-key:3","Secret":"REDACTED"}]'

# ---------- PreToolUse: 触发条件 ----------

@test "non-push commands pass through: exit 0, no output, scanner not invoked" {
  stub_betterleaks 1 "$FINDING"
  add_ahead_commit
  for cmd in "git status" "git commit -m x" "git add -A && git commit -m x" "git log | grep push" "echo pushing" "npm run push-notify" "git stash push -m wip" "git config remote.origin.push HEAD" "git remote show origin | grep -i push"; do
    run_pre "$cmd"
    [ "$status" -eq 0 ] || { echo "cmd=$cmd status=$status"; false; }
    [ -z "$output" ] || { echo "cmd=$cmd output=$output"; false; }
  done
  [ ! -s "$STUB_LOG" ] || { echo "scanner was invoked:"; cat "$STUB_LOG"; false; }
}

@test "push command variants all trigger the scan" {
  stub_betterleaks 0
  add_ahead_commit
  for cmd in "git push" "git push origin main" "git push -u origin HEAD" "git -C \"$REPO\" push" "git --no-pager push" "git -c push.default=current push" "git add -A && git commit -m x && git push" "cd \"$REPO\" && git push --force-with-lease" "git stash push -m wip && git push"; do
    : > "$STUB_LOG"
    run_pre "$cmd"
    [ "$status" -eq 0 ] || { echo "cmd=$cmd status=$status"; false; }
    [ -s "$STUB_LOG" ] || { echo "scanner not invoked for: $cmd"; false; }
  done
}

@test "GOX_GUARD_SKIP=1 bypasses everything (exit 0, no output, scanner not invoked)" {
  stub_betterleaks 1 "$FINDING"
  add_ahead_commit
  run env GOX_GUARD_SKIP=1 PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" PreToolUse <<EOF
{"tool_name":"Bash","cwd":"$REPO","tool_input":{"command":"git push"}}
EOF
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$STUB_LOG" ]
}

@test "cwd outside any git repo passes through (git itself will fail the push)" {
  stub_betterleaks 1 "$FINDING"
  run env PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" PreToolUse <<EOF
{"tool_name":"Bash","cwd":"$BATS_TEST_TMPDIR","tool_input":{"command":"git push"}}
EOF
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$STUB_LOG" ]
}

@test "nothing ahead of the remote: allow without invoking the scanner" {
  stub_betterleaks 1 "$FINDING"
  run_pre "git push"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$STUB_LOG" ]
}

# ---------- PreToolUse: 扫描结果 ----------

@test "clean scan (exit 0) allows the push silently" {
  stub_betterleaks 0
  add_ahead_commit
  run_pre "git push"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "scanner is invoked with the not-on-any-remote range, redaction on, validation off" {
  stub_betterleaks 0
  add_ahead_commit
  run_pre "git push"
  args="$(cat "$STUB_LOG")"
  [[ "$args" == *"git "* ]]
  [[ "$args" == *"--log-opts="*"HEAD --not --remotes"* ]] || { echo "args=$args"; false; }
  [[ "$args" == *"--redact"* ]]
  [[ "$args" != *"--validation"* ]]
  [[ "$args" == *"--no-banner"* ]]
}

@test "git push --all widens the range to every local branch" {
  stub_betterleaks 0
  add_ahead_commit
  run_pre "git push --all"
  args="$(cat "$STUB_LOG")"
  [[ "$args" == *"--branches --not --remotes"* ]] || { echo "args=$args"; false; }
}

@test "findings (exit 1) deny the push with a redacted summary and the triage protocol" {
  stub_betterleaks 1 "$FINDING"
  add_ahead_commit
  run_pre "git push"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  reason="$(echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason')"
  grep -q "aws-access-key" <<<"$reason"
  grep -q "config.txt:3" <<<"$reason"
  grep -q "01234567" <<<"$reason"
  # 协议四步：判断 / 真密钥 / 单行误报 / 已提交或成规律的误报
  grep -qi "real secret or a false positive" <<<"$reason"
  grep -q "rotate" <<<"$reason"
  grep -q "betterleaks:allow" <<<"$reason"
  grep -q ".betterleaksignore" <<<"$reason"
  grep -q "Never allowlist a real secret" <<<"$reason"
  grep -q "GOX_GUARD_SKIP=1" <<<"$reason"
  # 密钥原文不得出现（stub 报告里 Secret 已 REDACTED，这里断言脚本没有另行打印该字段）
  ! grep -q '"Secret"' <<<"$reason"
}

@test "scanner failure (unexpected exit code) denies with the error, not a silent allow" {
  cat > "$STUB_DIR/betterleaks" <<'EOF'
#!/usr/bin/env bash
echo "fatal: something broke" >&2
exit 126
EOF
  chmod +x "$STUB_DIR/betterleaks"
  add_ahead_commit
  run_pre "git push"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  reason="$(echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason')"
  grep -q "something broke" <<<"$reason"
  grep -q "GOX_GUARD_SKIP=1" <<<"$reason"
}

# ---------- 缺工具 ----------

@test "betterleaks missing: deny the push, tell the model to ask the user to install (never self-install)" {
  add_ahead_commit
  run env PATH="/usr/bin:/bin:/opt/homebrew/bin" bash "$HOOK" PreToolUse <<EOF
{"tool_name":"Bash","cwd":"$REPO","tool_input":{"command":"git push"}}
EOF
  # 本机若真装了 betterleaks 则此用例不成立，跳过
  command -v betterleaks >/dev/null 2>&1 && skip "betterleaks is installed on this machine"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  reason="$(echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason')"
  grep -q "brew install betterleaks" <<<"$reason"
  grep -qi "do not install it yourself" <<<"$reason"
}

@test "SessionStart with betterleaks missing: additionalContext names the gate and the install command" {
  run env PATH="/usr/bin:/bin:/opt/homebrew/bin" bash "$HOOK" SessionStart
  command -v betterleaks >/dev/null 2>&1 && skip "betterleaks is installed on this machine"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  ctx="$(echo "$output" | jq -er '.hookSpecificOutput.additionalContext')"
  grep -q "gox-guard" <<<"$ctx"
  grep -q "git push" <<<"$ctx"
  grep -q "brew install betterleaks" <<<"$ctx"
  grep -qi "do not install it yourself" <<<"$ctx"
}

@test "SessionStart with betterleaks present: silent (no tokens spent)" {
  stub_betterleaks 0
  run env PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" SessionStart
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- fail-open 形状 ----------

@test "never exits non-zero: unknown event, bad JSON, empty stdin, missing jq" {
  run bash "$HOOK" BogusEvent
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$HOOK" PreToolUse <<<'not-json'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$HOOK" PreToolUse </dev/null
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run env PATH="/bin" bash "$HOOK" PreToolUse <<<'{"tool_input":{"command":"git push"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "script never enables validation and always redacts (static check)" {
  ! grep -q -- '--validation' "$HOOK"
  grep -q -- '--redact' "$HOOK"
}
