#!/usr/bin/env bash
# gox-guard：agent 侧的密钥闸门。只在 Claude 要执行 `git push` 时介入，
# 用 betterleaks 扫"本地有、任何远端都没有"的那段提交；有发现就拒绝这次 push。
# 不碰 commit、不写用户 repo、不自动安装任何东西。
#
# 事件名由 hooks.json 以 $1 传入：
#   SessionStart —— 只检查依赖（jq、betterleaks）是否可用，缺失时提示一句；齐全时零输出。
#   PreToolUse   —— 从 stdin 的 hook 输入 JSON 里取 Bash 命令与 cwd，判定是否 push。
#
# 退出码：永远 0（Claude Code hook 规范，非零会干扰会话）。"拦下"通过 stdout 的
# permissionDecision=deny 表达，不靠退出码。这也是 shell 规范里 hook 脚本的结构性例外：
# 只 set -u，不用 -e/pipefail。
#
# 取舍：
#   1. 缺依赖时拦而不是放：安全闸门静默放行等于没有；用户装一次就好。
#   2. 扫描器自身出错也拦：把错误原样交给模型，由人决定是否绕过。
#   3. 唯一逃生口 GOX_GUARD_SKIP=1，供没有 brew / Go 的机器应急。
#   4. 给模型的文案尽量短：只有拦下时才有输出；发现列表一行一条并设上限；处置规则两句说完，
#      不附手册（模型本来就会 git，多余的说明只会堆上下文）。
set -u

EVENT="${1:-}"
case "$EVENT" in
  SessionStart|PreToolUse) ;;
  *) exit 0 ;;
esac

MAX_FINDINGS=10

# ---------- 文案（全部集中在这里；反引号是给模型看的 markdown，不是命令替换） ----------
# shellcheck disable=SC2016
{
  # 依赖缺失：安装命令 + 不自装 + 逃生口。SessionStart 与 PreToolUse 共用同一句。
  MSG_NO_JQ='jq is not installed, so gox-guard cannot read hook input. Ask the user to run `brew install jq` (do not install it yourself).'
  MSG_NO_SCANNER='betterleaks is not installed. Ask the user to run `brew install betterleaks` (do not install it yourself).'
  MSG_BYPASS='Bypass only if the user explicitly asks: GOX_GUARD_SKIP=1.'
  # 有发现时的两句裁定规则：真密钥 / 误报（单行、已提交、成规律三种出口）/ 绝不加白真值
  MSG_TRIAGE='Real secret: remove it from the commit(s), then tell the user to rotate it. False positive: `# betterleaks:allow` on that line, append its fp to `.betterleaksignore`, or for a recurring pattern add an allowlist to `.betterleaks.toml`. Never allowlist a real secret.'
}

# `git [全局选项...] push`：git 与 push 之间只允许以 - 开头的选项及其可选取值（-C dir、-c k=v、
# --no-pager），所以 `git stash push`、`git log | grep push`、`git config remote.origin.push`
# 都不算。段由 ; & | 分隔，链式命令里任一段命中即可。
PUSH_RE='(^|[^[:alnum:]_./-])git([[:space:]]+-[^[:space:];&|]*([[:space:]]+[^-[:space:];&|][^[:space:];&|]*)?)*[[:space:]]+push([[:space:]]|$|[;&|)])'

# ---------- 输出 ----------
# 没有 jq 时也要能输出 JSON：文案里不含双引号与反斜杠，直接拼字符串即安全。
emit_context() {  # $1 = 事件名  $2 = 文案
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"[gox-guard] %s"}}\n' "$1" "$2"
  exit 0
}
emit_deny_plain() {  # 无 jq 版：仅用于固定文案
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[gox-guard] Push blocked: %s"}}\n' "$1"
  exit 0
}
emit_deny() {  # 有 jq 版：文案含动态内容（文件名、错误输出），交给 jq 转义
  jq -n --arg reason "[gox-guard] Push blocked: $1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' \
    || exit 0
  exit 0
}

# 找扫描器：允许 GOX_GUARD_BIN 显式指定（测试 / 非标准路径），否则查 PATH
find_scanner() {
  if [ -n "${GOX_GUARD_BIN:-}" ] && [ -x "${GOX_GUARD_BIN}" ]; then
    printf '%s\n' "$GOX_GUARD_BIN"
    return 0
  fi
  command -v betterleaks 2>/dev/null
}

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# ---------- SessionStart：只在缺依赖时说一句 ----------
if [ "$EVENT" = "SessionStart" ]; then
  [ "$HAVE_JQ" -eq 1 ] || emit_context SessionStart "This session blocks \`git push\` until its secret scan can run. $MSG_NO_JQ"
  find_scanner >/dev/null || emit_context SessionStart "This session scans pending commits for secrets before \`git push\`; pushes are blocked until the scanner is present. $MSG_NO_SCANNER"
  exit 0
fi

# ---------- PreToolUse ----------
[ "${GOX_GUARD_SKIP:-}" = "1" ] && exit 0
[ -t 0 ] && exit 0                       # 没有 stdin 的调用（手工执行）不是 hook 场景

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

# 缺 jq：不能解析输入，push 判定退化为对原始 JSON 跑同一条正则；命中即拦并提示装 jq
if [ "$HAVE_JQ" -eq 0 ]; then
  printf '%s' "$INPUT" | grep -Eq "$PUSH_RE" || exit 0
  emit_deny_plain "pending commits cannot be checked. $MSG_NO_JQ $MSG_BYPASS"
fi

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0
printf '%s' "$CMD" | grep -Eq "$PUSH_RE" || exit 0

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
REPO="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO" ] || exit 0                 # 不在 git 仓库里，让 git 自己报错

# 区间：默认 HEAD 上不在任何远端的提交；--all / --mirror 时扩到所有本地分支
RANGE="HEAD --not --remotes"
case "$CMD" in *--all*|*--mirror*) RANGE="--branches --not --remotes" ;; esac

# 没有待推送的提交（或空仓库）就不必扫
# shellcheck disable=SC2086
AHEAD="$(git -C "$REPO" rev-list --count $RANGE 2>/dev/null || echo 0)"
[ "${AHEAD:-0}" -gt 0 ] 2>/dev/null || exit 0

SCANNER="$(find_scanner || true)"
[ -n "$SCANNER" ] || emit_deny "$AHEAD pending commit(s) cannot be checked. $MSG_NO_SCANNER $MSG_BYPASS"

# 从仓库根运行：betterleaks 在目标目录解析 .betterleaks.toml / .gitleaks.toml 与 .betterleaksignore。
# --redact 是硬要求（发现会进模型上下文与 transcript）；绝不开 validation（会把疑似密钥发往厂商 API）。
STDERR_FILE="$(mktemp 2>/dev/null || echo /tmp/gox-guard.$$)"
REPORT="$(cd "$REPO" && "$SCANNER" git . --log-opts="$RANGE" --redact --no-banner --no-color \
  --timeout 60 -r - -f json --log-level error 2>"$STDERR_FILE")"
RC=$?
ERR="$(tail -n 5 "$STDERR_FILE" 2>/dev/null || true)"
rm -f "$STDERR_FILE"

case "$RC" in
  0) exit 0 ;;                           # 干净：零输出
  1) ;;                                  # 有发现：往下组装 deny
  *) emit_deny "the scanner failed (exit $RC), so $AHEAD pending commit(s) could not be checked.
$ERR
Fix that (or ask the user to), then retry. $MSG_BYPASS" ;;
esac

# 干净时报告是 null；有发现时是数组。一行一条：规则 文件:行 @提交 fp=指纹；超过上限只报数量。
# 只取定位字段，不取 Secret/Match（已 redact，但也不回显）。
COUNT="$(printf '%s' "$REPORT" | jq -r '(. // []) | length' 2>/dev/null || echo "?")"
LIST="$(printf '%s' "$REPORT" | jq -r --argjson n "$MAX_FINDINGS" \
  '(. // []) | .[:$n][] | "\(.RuleID)  \(.File):\(.StartLine)  @\(.Commit[0:8])  fp=\(.Fingerprint)"' 2>/dev/null || true)"
MORE=""
[ "$COUNT" != "?" ] && [ "$COUNT" -gt "$MAX_FINDINGS" ] 2>/dev/null && MORE="
... and $((COUNT - MAX_FINDINGS)) more (run the scanner yourself for the full list)."

emit_deny "$COUNT potential secret(s) in $AHEAD pending commit(s).
$LIST$MORE
$MSG_TRIAGE"
