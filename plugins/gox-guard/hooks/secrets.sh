#!/usr/bin/env bash
# gox-guard / secrets：Claude 执行 `git push` 前，用 betterleaks 扫"本地有、任何远端都没有"
# 的那段提交；有发现就拒绝这次 push。不碰 commit，不写用户 repo，不安装任何东西。
#
# 事件名由 hooks.json 以 $1 传入：
#   SessionStart —— 检查依赖（jq、betterleaks），缺失时提示一句，齐全时零输出。
#   PreToolUse   —— 从 stdin 的 hook 输入取 Bash 命令与 cwd，命中 push 才扫描。
#
# 退出码永远 0（hook 非零会干扰会话）。拦截写在 stdout，不靠退出码。
# Claude：hookSpecificOutput.permissionDecision=deny。
# 因此只 set -u，不用 -e/pipefail。依赖缺失、扫描器出错都拦（闸门静默放行等于没有），
# 唯一逃生口是环境变量 GOX_GUARD_SKIP=1。给模型的文案只在拦截时出现，并尽量短。
set -u

EVENT="${1:-}"
case "$EVENT" in
  SessionStart|PreToolUse) ;;
  *) exit 0 ;;
esac

MAX_FINDINGS=10

# ---------- 文案（反引号是给模型看的 markdown） ----------
# shellcheck disable=SC2016
{
  MSG_NO_JQ='jq is not installed, so gox-guard cannot read hook input. Ask the user to run `brew install jq` (do not install it yourself).'
  MSG_NO_SCANNER='betterleaks is not installed. Ask the user to run `brew install betterleaks` (do not install it yourself).'
  MSG_BYPASS='Bypass only if the user explicitly asks: GOX_GUARD_SKIP=1.'
  MSG_EMPTY_CONFIG='`.betterleaks.toml` has neither `[[rules]]` nor `[extend]`, so the scan would check nothing. It needs `[extend]` with `useDefault = true`; ask the user before changing scanner config.'
  MSG_TRIAGE='Real secret: remove it from the commit(s), then tell the user to rotate it. False positive: a `betterleaks:allow` comment on that line in the commit that adds it, or its fp in `.betterleaksignore` at the repo root when the line is already committed. Never allowlist a real secret. Steps: skill `secret-triage`.'
}

# `git [全局选项...] push`：git 与 push 之间只允许 - 开头的选项及其取值（-C dir、-c k=v），
# 所以 `git stash push`、`git log | grep push` 都不算；段由 ; & | 分隔，链式命令任一段命中即可。
SHELL_PART="(\"[^\"]*\"|'[^']*'|[^[:space:];&|\"'])"
# 同时覆盖直接路径及带引号的程序词；是否可扫描仍由范围解析决定。
GIT_WORD="(git|[^[:space:];&|\"']*/git|\"[^\"]*/git\"|'[^']*/git'|\"git\"|'git')"
PUSH_RE="(^|[^[:alnum:]_./-])${GIT_WORD}([[:space:]]+-${SHELL_PART}*([[:space:]]+${SHELL_PART}+)?)*[[:space:]]+push([[:space:]]|$|[;&|)\"'\`])"

# ---------- 输出 ----------
# 固定文案不含双引号与反斜杠，可以不经 jq 直接拼 JSON；含动态内容的 deny 交给 jq 转义。
# 输出固定为 Claude 协议；其他平台由各自入口适配。
emit_context() {  # $1 事件名  $2 文案
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"[gox-guard/secrets] %s"}}\n' "$1" "$2"
  exit 0
}
emit_deny_plain() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[gox-guard/secrets] Push blocked: %s"}}\n' "$1"
  exit 0
}
emit_deny() {
  jq -n --arg reason "[gox-guard/secrets] Push blocked: $1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' \
    || exit 0
  exit 0
}

# GOX_GUARD_BIN 可显式指定扫描器路径（测试或非标准安装位置），否则查 PATH
find_scanner() {
  if [ -n "${GOX_GUARD_BIN:-}" ] && [ -x "${GOX_GUARD_BIN}" ]; then
    printf '%s\n' "$GOX_GUARD_BIN"
    return 0
  fi
  command -v betterleaks 2>/dev/null
}

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# ---------- SessionStart ----------
if [ "$EVENT" = "SessionStart" ]; then
  [ "$HAVE_JQ" -eq 1 ] || emit_context SessionStart "This session blocks \`git push\` until its secret scan can run. $MSG_NO_JQ"
  find_scanner >/dev/null || emit_context SessionStart "This session scans pending commits for secrets before \`git push\`; pushes are blocked until the scanner is present. $MSG_NO_SCANNER"
  exit 0
fi

# ---------- PreToolUse ----------
[ "${GOX_GUARD_SKIP:-}" = "1" ] && exit 0
[ -t 0 ] && exit 0                       # 没有 stdin 就不是 hook 调用

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

# 没有 jq 解析不了输入：对原始 JSON 跑同一条正则，命中即拦并要求装 jq
if [ "$HAVE_JQ" -eq 0 ]; then
  # 还原 JSON 中的转义双引号，保留路径里的空格；正则也接受字符串结束引号。
  RAW="${INPUT//\\\"/\"}"
  printf '%s' "$RAW" | grep -Eq "$PUSH_RE" || exit 0
  emit_deny_plain "pending commits cannot be checked. $MSG_NO_JQ $MSG_BYPASS"
fi

# 按 Claude 协议读取命令；其他平台的字段差异由入口适配。
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0
printf '%s' "$CMD" | grep -Eq "$PUSH_RE" || exit 0

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$CWD" ] || CWD="$PWD"
GUARD_LIB_DIR="$(cd "$(dirname "$0")/../lib" 2>/dev/null && pwd)" || emit_deny "push scope helper is missing. Reinstall gox-guard."
# 搜索/打印参数中的 git push 不代表执行；只有完整确认的文本命令可跳过。
# 分词失败或 helper 缺失继续走原来的保守拒绝路径。
if printf '%s' "$CMD" | jq -Rse --arg mode text -f "$GUARD_LIB_DIR/literal-args.jq" >/dev/null 2>&1; then
  exit 0
fi
# shellcheck source=../lib/push-scope.sh
source "$GUARD_LIB_DIR/push-scope.sh" || emit_deny "push scope helper could not be loaded."
resolve_push_scope "$CMD" "$CWD" || emit_deny "${SCOPE_ERROR:-the push repository or source commits could not be determined safely. Run git push as a separate command with literal paths and explicit source refs; avoid shell expansions and unsupported options.}"
[ "${#RANGE[@]}" -gt 0 ] || exit 0
RANGE+=(--not --remotes)
AHEAD="$(git -C "$REPO" rev-list --count "${RANGE[@]}" 2>/dev/null)" || emit_deny "pending commits could not be enumerated. Check the repository and push source refs."
[ "$AHEAD" -gt 0 ] || exit 0   # 没有待推送提交，不必扫。

SCANNER="$(find_scanner || true)"
[ -n "$SCANNER" ] || emit_deny "$AHEAD pending commit(s) cannot be checked. $MSG_NO_SCANNER $MSG_BYPASS"

# 配置由调用方显式选择：betterleaks 1.10 起不再自动发现仓库内的 TOML。环境变量已指定时不干预；
# 否则用仓库根的 .betterleaks.toml（与 ignore 文件一样取自工作树）。既无规则也不继承默认规则的
# 配置会让扫描什么都不查，按闸门失效拒绝。
CONFIG=""
if [ -z "${BETTERLEAKS_CONFIG:-}${BETTERLEAKS_CONFIG_TOML:-}${GITLEAKS_CONFIG:-}${GITLEAKS_CONFIG_TOML:-}" ] \
  && [ -f "$REPO/.betterleaks.toml" ]; then
  grep -Eq '^[[:space:]]*\[(extend\]|\[rules\]\])' "$REPO/.betterleaks.toml" || emit_deny "$MSG_EMPTY_CONFIG"
  CONFIG=.betterleaks.toml
fi

# 在仓库根运行，使相对配置路径与 ignore 文件对应目标仓库。
# --redact 必须常开（发现会进模型上下文与 transcript）；绝不开 validation（会把疑似密钥发往厂商 API）。
STDERR_FILE="$(mktemp 2>/dev/null || echo /tmp/gox-guard.$$)"
REPORT="$(cd "$REPO" && "$SCANNER" git . ${CONFIG:+-c "$CONFIG"} --log-opts="${RANGE[*]}" --redact --no-banner --no-color \
  --timeout 60 -r - -f json --log-level error 2>"$STDERR_FILE")"
RC=$?
ERR="$(tail -n 5 "$STDERR_FILE" 2>/dev/null || true)"
rm -f "$STDERR_FILE"

case "$RC" in
  0) exit 0 ;;                           # 干净
  1) ;;                                  # 有发现
  *) emit_deny "the scanner failed (exit $RC), so $AHEAD pending commit(s) could not be checked.
$ERR
Fix that (or ask the user to), then retry. $MSG_BYPASS" ;;
esac

# 报告干净时是 null，有发现时是数组。一行一条：规则 文件:行 @提交 fp=指纹；超过上限报数量，
# 并附同一区间、同样脱敏的只读重扫命令。只取定位字段，不回显 Secret / Match。
# shellcheck disable=SC2016
LINE_FMT='"\(.RuleID)  \(.File):\(.StartLine)  @\(.Commit[0:8])  fp=\(.Fingerprint)"'
COUNT="$(printf '%s' "$REPORT" | jq -r '(. // []) | length' 2>/dev/null || echo "?")"
LIST="$(printf '%s' "$REPORT" | jq -r --argjson n "$MAX_FINDINGS" \
  "(. // []) | .[:\$n][] | $LINE_FMT" 2>/dev/null || true)"
MORE=""
[ "$COUNT" != "?" ] && [ "$COUNT" -gt "$MAX_FINDINGS" ] 2>/dev/null && MORE="
... and $((COUNT - MAX_FINDINGS)) more. Full list (read-only):
$(printf 'cd %q && %q' "$REPO" "$SCANNER") git . ${CONFIG:+-c $CONFIG }--log-opts=\"${RANGE[*]}\" --redact --no-banner --no-color --log-level error -r - -f json | jq -r '.[] | $LINE_FMT'"

emit_deny "$COUNT potential secret(s) in $AHEAD pending commit(s).
$LIST$MORE
$MSG_TRIAGE"
