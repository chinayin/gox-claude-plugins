#!/usr/bin/env bash
# gox-guard：agent 侧的密钥闸门。只在 Claude 要执行 `git push` 时介入，
# 用 betterleaks 扫"本地有、任何远端都没有"的那段提交；有发现就拒绝这次 push，
# 并把处置协议交给模型。不碰 commit、不写用户 repo、不自动安装任何东西。
#
# 事件名由 hooks.json 以 $1 传入：
#   SessionStart —— 只检查 betterleaks 是否可用，缺失时提示一句；可用时零输出。
#   PreToolUse   —— 从 stdin 的 hook 输入 JSON 里取 Bash 命令与 cwd，判定是否 push。
#
# 退出码：永远 0（Claude Code hook 规范，非零会干扰会话）。"拦下"通过 stdout 的
# permissionDecision=deny 表达，不靠退出码。这也是 shell 规范里 hook 脚本的结构性例外：
# 只 set -u，不用 -e/pipefail。
#
# 三个刻意的取舍：
#   1. 缺工具时拦而不是放：安全闸门静默放行等于没有；用户装一次就好。
#   2. 扫描器自身出错也拦：把错误原样交给模型，由人决定是否绕过。
#   3. 唯一逃生口 GOX_GUARD_SKIP=1，供没有 brew / Go 的机器应急。
set -u

EVENT="${1:-}"
case "$EVENT" in
  SessionStart|PreToolUse) ;;
  *) exit 0 ;;
esac

# 缺 jq 无法解析 hook 输入，只能放行（SessionStart 也不再输出，避免半残提示）
command -v jq >/dev/null 2>&1 || exit 0

# 反引号是给模型看的 markdown，不是命令替换
# shellcheck disable=SC2016
INSTALL_HINT='Install it with `brew install betterleaks` (or `go install github.com/betterleaks/betterleaks@latest`). Do not install it yourself; ask the user to.'

# 找扫描器：允许 GOX_GUARD_BIN 显式指定（测试 / 非标准路径），否则查 PATH
find_scanner() {
  if [ -n "${GOX_GUARD_BIN:-}" ] && [ -x "${GOX_GUARD_BIN}" ]; then
    printf '%s\n' "$GOX_GUARD_BIN"
    return 0
  fi
  command -v betterleaks 2>/dev/null
}

emit_deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' \
    || exit 0
  exit 0
}

# ---------- SessionStart ----------
if [ "$EVENT" = "SessionStart" ]; then
  find_scanner >/dev/null && exit 0
  CTX="[gox-guard] This session gates \`git push\`: before Claude pushes, the commits not yet on any remote are scanned for secrets with betterleaks. betterleaks is NOT installed on this machine, so pushes from this session will be blocked until it is. $INSTALL_HINT"
  jq -n --arg ctx "$CTX" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
    || exit 0
  exit 0
fi

# ---------- PreToolUse ----------
[ "${GOX_GUARD_SKIP:-}" = "1" ] && exit 0
[ -t 0 ] && exit 0                       # 没有 stdin 的调用（手工执行）不是 hook 场景

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

# 只认 `git [全局选项...] push`：git 与 push 之间只允许以 - 开头的选项及其可选取值
# （-C dir、-c k=v、--no-pager），所以 `git stash push`、`git log | grep push`、
# `git config remote.origin.push` 都不算。段由 ; & | 分隔，链式命令里任一段命中即可。
printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_./-])git([[:space:]]+-[^[:space:];&|]*([[:space:]]+[^-[:space:];&|][^[:space:];&|]*)?)*[[:space:]]+push([[:space:]]|$|[;&|)])' || exit 0

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
if [ -z "$SCANNER" ]; then
  emit_deny "[gox-guard] Push blocked: this repo has $AHEAD commit(s) not yet on any remote, and betterleaks (the secret scanner) is not installed, so they cannot be checked. $INSTALL_HINT Emergency bypass for a machine that cannot install it: run the push with GOX_GUARD_SKIP=1 and tell the user you did."
fi

# 从仓库根运行：betterleaks 在目标目录解析 .betterleaks.toml / .gitleaks.toml 与 .betterleaksignore。
# --redact 是硬要求（发现会进模型上下文与 transcript）；绝不开 validation（会把疑似密钥发往厂商 API）。
STDERR_FILE="$(mktemp 2>/dev/null || echo /tmp/gox-guard.$$)"
REPORT="$(cd "$REPO" && "$SCANNER" git . --log-opts="$RANGE" --redact --no-banner --no-color \
  --timeout 60 -r - -f json --log-level error 2>"$STDERR_FILE")"
RC=$?
ERR="$(tail -n 20 "$STDERR_FILE" 2>/dev/null || true)"
rm -f "$STDERR_FILE"

case "$RC" in
  0) exit 0 ;;
  1) ;;                                  # 有发现，往下组装 deny
  *)
    emit_deny "[gox-guard] Push blocked: the secret scanner failed (exit $RC), so the $AHEAD pending commit(s) could not be checked.
$ERR
Fix the scanner problem (or ask the user to), then retry. Emergency bypass: run the push with GOX_GUARD_SKIP=1 and tell the user you did."
    ;;
esac

# 干净时报告是 null；有发现时是数组。只取定位字段，不取 Secret/Match（已 redact，但也不回显）。
SUMMARY="$(printf '%s' "$REPORT" | jq -r '(. // []) | .[] | "- \(.RuleID)  \(.File):\(.StartLine)  commit \(.Commit[0:8])\n    fingerprint: \(.Fingerprint)"' 2>/dev/null || true)"
COUNT="$(printf '%s' "$REPORT" | jq -r '(. // []) | length' 2>/dev/null || echo "?")"

emit_deny "[gox-guard] Push blocked: betterleaks found $COUNT potential secret(s) in the $AHEAD commit(s) not yet on any remote.
$SUMMARY
Triage before pushing again. For each finding decide whether it is a real secret or a false positive:
1. Real secret: remove it from the commit(s) it is in (e.g. \`git reset --soft <last clean commit>\`, fix the files, recommit). Then tell the user the value already exists in local history and should be rotated. Never allowlist a real secret.
2. False positive on a single line: add a \`# betterleaks:allow\` comment on that line and recommit/amend.
3. False positive already committed (rewriting is not worth it), or a recurring pattern (fixtures, examples): append the finding's fingerprint to \`.betterleaksignore\` at the repo root, or add a path/regex allowlist entry to \`.betterleaks.toml\`. Commit that file like any other change so the team sees it.
Then run the push again. Emergency bypass only if the user explicitly asks: GOX_GUARD_SKIP=1."
