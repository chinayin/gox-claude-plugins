#!/usr/bin/env bash
# 手动评估：统计一批提示词各自让模型加载了哪个技能（shell / bashly）。
# 会调用模型，耗额度且结果不确定，所以不进 make test。
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-trigger.sh [--runs N] <triggers.tsv>

For each query, start a real model session with the plugin loaded and report
which of the shell / bashly skills it loads before it first writes a file.
A session that has not written anything after 180 seconds is stopped too.

  <triggers.tsv>   tab-separated columns: expect, fixture, query
                     expect   shell (bashly must not load) | bashly | none
                     fixture  directory copied into the session's cwd, relative
                              to this script; "-" for an empty directory
  --runs N         sessions per query (default: 3)

Environment:
  EVAL_MODEL       model alias or id (default: sonnet)

Prints one line per session: result, expect, loaded, query; then a summary.
Exit codes: 0 every session passed, 1 usage error or a failed session,
            2 precondition not met
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

RUNS=3
FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) [ $# -ge 2 ] || die "--runs needs a value"; RUNS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) [ -z "${FILE}" ] || die "unexpected argument: $1"; FILE="$1"; shift ;;
  esac
done
[ -n "${FILE}" ] || { usage >&2; die "missing <triggers.tsv>"; }
[[ "${RUNS}" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive integer: ${RUNS}"

command -v claude >/dev/null 2>&1 || { echo "Error: claude not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found" >&2; exit 2; }
[ -f "${FILE}" ] || { echo "Error: no such file: ${FILE}" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "${HERE}/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# 与 run-case.sh 相同的隔离与沙箱：模型的命令不需要审批，也写不出工作目录
SANDBOX='{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true,"allowUnsandboxedCommands":false}}'
MAX_SECONDS=180

TOOL_USE='select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")'

# 跑一次会话，模型第一次写文件或超时就终止；输出此前加载的技能（逗号分隔，没有则 none）
loaded_skills() {
  local fixture="$1" query="$2" dir pid out start="${SECONDS}"
  dir="$(mktemp -d "${TMP}/run.XXXXXX")"
  mkdir "${dir}/work"
  if [ "${fixture}" != "-" ]; then
    cp -R "${HERE}/${fixture}/." "${dir}/work/"
  fi
  (cd "${dir}/work" && exec claude -p "${query}" --model "${EVAL_MODEL:-sonnet}" \
    --setting-sources project --plugin-dir "${PLUGIN_DIR}" \
    --permission-mode acceptEdits --allowedTools Bash --settings "${SANDBOX}" \
    --output-format stream-json --verbose </dev/null >"${dir}/t.jsonl" 2>/dev/null) &
  pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "${MAX_SECONDS}" ] \
      || jq -e "${TOOL_USE} | select(.name==\"Write\" or .name==\"Edit\")" "${dir}/t.jsonl" >/dev/null 2>&1; then
      kill "${pid}" 2>/dev/null || true
      break
    fi
    sleep 1
  done
  wait "${pid}" 2>/dev/null || true
  out="$(jq -r "${TOOL_USE} | select(.name==\"Skill\") | .input.skill" "${dir}/t.jsonl" 2>/dev/null \
    | sed 's/^gox-code-rules://' | grep -E '^(shell|bashly)$' | sort -u | paste -sd, - || true)"
  echo "${out:-none}"
}

passes() {
  local expect="$1" loaded="$2"
  case "${expect}" in
    shell) [ "${loaded}" = "shell" ] ;;
    bashly) [[ ",${loaded}," == *,bashly,* ]] ;;
    none) [ "${loaded}" = "none" ] ;;
  esac
}

PASS=0
FAIL=0
while IFS=$'\t' read -r expect fixture query; do
  [ -n "${expect}" ] || continue
  case "${expect}" in
    shell|bashly|none) ;;
    *) die "unknown expect value: ${expect}" ;;
  esac
  [ "${fixture}" = "-" ] || [ -d "${HERE}/${fixture}" ] || die "no such fixture: ${fixture}"
  for ((i = 0; i < RUNS; i++)); do
    loaded="$(loaded_skills "${fixture}" "${query}")"
    if passes "${expect}" "${loaded}"; then
      result="[PASS]"
      PASS=$((PASS + 1))
    else
      result="[FAIL]"
      FAIL=$((FAIL + 1))
    fi
    printf '%s\t%s\t%s\t%s\n' "${result}" "${expect}" "${loaded}" "${query}"
  done
done <"${FILE}"

echo "result: PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
