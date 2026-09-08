#!/usr/bin/env bats
#
# gox-guard / secrets：什么时候扫、扫什么区间、拦下时说什么、缺依赖怎么办。
# 扫描器用 PATH 上的 stub 模拟（干净 / 有发现 / 出错 / 未安装）；git 操作只发生在
# $BATS_TEST_TMPDIR 下的临时仓库里。

HOOK="$BATS_TEST_DIRNAME/../hooks/secrets.sh"

setup() {
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"    # stub 每次被调用追加一行参数
  : > "$STUB_LOG"

  # 有远端、已推送一次的临时仓库；需要待推送提交的用例再调 add_ahead_commit
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

# stub_betterleaks <exit-code> [json-report]：记录参数，按要求退出，报告打到 stdout（模拟 -r -）
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

add_ahead_commit() {
  echo "x=1" > "$REPO/config.txt"
  git -C "$REPO" add config.txt
  git -C "$REPO" commit -qm ahead
}

# run_pre <command>：以 PreToolUse 的 stdin 形状调用 hook
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

@test "findings (exit 1) deny the push with one line per finding and the verdict rule" {
  stub_betterleaks 1 "$FINDING"
  add_ahead_commit
  run_pre "git push"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  reason="$(echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason')"
  # 一行一条：规则 文件:行 @提交 fp=指纹
  grep -qE '^aws-access-key +config.txt:3 +@01234567 +fp=0123456789abcdef:config.txt:aws-access-key:3$' <<<"$reason"
  # 裁定规则：真密钥删除并轮换 / 误报三个出口 / 绝不加白真值
  grep -q "rotate" <<<"$reason"
  grep -q "betterleaks:allow" <<<"$reason"
  grep -q ".betterleaksignore" <<<"$reason"
  grep -q ".betterleaks.toml" <<<"$reason"
  grep -q "Never allowlist a real secret" <<<"$reason"
  # 有发现时不提逃生口
  ! grep -q "GOX_GUARD_SKIP" <<<"$reason"
  # 不回显 Secret 字段
  ! grep -q '"Secret"' <<<"$reason"
  # 单条发现的文案不超过 600 字符
  [ "${#reason}" -lt 600 ] || { echo "reason too long: ${#reason}"; false; }
}

@test "findings list is capped at 10 with a count of the rest" {
  many="$(jq -nc '[range(0;14) | {RuleID:"generic-api-key",File:"f\(.).txt",StartLine:1,Commit:"abcdef0123456789",Fingerprint:"abcdef01:f\(.).txt:generic-api-key:1"}]')"
  stub_betterleaks 1 "$many"
  add_ahead_commit
  run_pre "git push"
  reason="$(echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason')"
  [ "$(grep -c '^generic-api-key ' <<<"$reason")" -eq 10 ]
  grep -q "and 4 more" <<<"$reason"
  grep -q "Push blocked: 14 potential secret" <<<"$reason"
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

# ---------- 缺 betterleaks ----------

@test "betterleaks missing: deny the push, tell the model to ask the user to install (never self-install)" {
  add_ahead_commit
  run env PATH="/usr/bin:/bin:/opt/homebrew/bin" bash "$HOOK" PreToolUse <<EOF
{"tool_name":"Bash","cwd":"$REPO","tool_input":{"command":"git push"}}
EOF
  command -v betterleaks >/dev/null 2>&1 && skip "betterleaks is installed on this machine"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  reason="$(echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason')"
  grep -q "brew install betterleaks" <<<"$reason"
  grep -qi "do not install it yourself" <<<"$reason"
  grep -q "GOX_GUARD_SKIP=1" <<<"$reason"
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
  [ "${#ctx}" -lt 300 ] || { echo "context too long: ${#ctx}"; false; }
}

@test "SessionStart with betterleaks present: silent (no tokens spent)" {
  stub_betterleaks 0
  run env PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" SessionStart
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- 退出码 ----------

@test "never exits non-zero: unknown event, bad JSON, empty stdin" {
  run bash "$HOOK" BogusEvent
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$HOOK" PreToolUse <<<'not-json'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$HOOK" PreToolUse </dev/null
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ---------- 缺 jq ----------
# 系统目录里可能自带 jq（新版 macOS 的 /usr/bin），所以搭一个只软链脚本所需工具、独缺 jq 的 PATH。

nojq_path() {
  local d="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$d"
  local t
  for t in bash sh git grep cat sed tail mktemp rm dirname env; do
    ln -sf "$(command -v "$t")" "$d/$t"
  done
  printf '%s' "$d"
}

@test "jq missing + push: deny with a fixed JSON naming jq (no silent allow)" {
  P="$(nojq_path)"
  run env PATH="$P" bash "$HOOK" PreToolUse <<<'{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q "brew install jq"
  echo "$output" | jq -er '.hookSpecificOutput.permissionDecisionReason' | grep -q "GOX_GUARD_SKIP=1"
}

@test "jq missing + non-push or GOX_GUARD_SKIP: exit 0, no output" {
  P="$(nojq_path)"
  run env PATH="$P" bash "$HOOK" PreToolUse <<<'{"tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run env PATH="$P" bash "$HOOK" PreToolUse <<<'{"tool_input":{"command":"git stash push -m wip"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run env GOX_GUARD_SKIP=1 PATH="$P" bash "$HOOK" PreToolUse <<<'{"tool_input":{"command":"git push"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "jq missing at SessionStart: fixed additionalContext names jq and the install command" {
  P="$(nojq_path)"
  run env PATH="$P" bash "$HOOK" SessionStart </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "brew install jq"
}

@test "script never enables validation and always redacts (static check)" {
  ! grep -q -- '--validation' "$HOOK"
  grep -q -- '--redact' "$HOOK"
}
