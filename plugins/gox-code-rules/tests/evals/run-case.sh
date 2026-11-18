#!/usr/bin/env bash
# 手动评估：让真实模型在隔离目录里做一个用例，产物留给该用例的 checks.bats 判分。
# 会调用模型，耗额度且结果不确定，所以不进 make test。
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-case.sh [--baseline] <case-dir> <out-dir>

Run one eval case with a real model and keep what it produced.

  <case-dir>   holds prompt.md and an optional fixture/ copied into the model's cwd
  <out-dir>    must not exist; receives work/ (the model's cwd) and transcript.jsonl
  --baseline   run without the plugin, to compare against

Environment:
  EVAL_MODEL   model alias or id (default: sonnet)

Prints the absolute <out-dir> on success.
Exit codes: 0 ok, 1 usage error or failed run, 2 precondition not met
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

BASELINE=0
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) BASELINE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[ "${#ARGS[@]}" -eq 2 ] || { usage >&2; die "expected <case-dir> and <out-dir>"; }
CASE_DIR="${ARGS[0]}"
OUT_DIR="${ARGS[1]}"

command -v claude >/dev/null 2>&1 || { echo "Error: claude not found" >&2; exit 2; }
[ -f "${CASE_DIR}/prompt.md" ] || { echo "Error: no prompt.md in ${CASE_DIR}" >&2; exit 2; }
[ ! -e "${OUT_DIR}" ] || die "out dir already exists: ${OUT_DIR}"

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROMPT="$(cat "${CASE_DIR}/prompt.md")"
mkdir -p "${OUT_DIR}/work"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"
if [ -d "${CASE_DIR}/fixture" ]; then
  cp -R "${CASE_DIR}/fixture/." "${OUT_DIR}/work/"
fi

# --setting-sources project：不读用户级设置，本机已装的插件和个人技能都不参与；
# sandbox：模型执行的命令只能写工作目录和 TMPDIR。
CMD=(claude -p "${PROMPT}" --model "${EVAL_MODEL:-sonnet}" --setting-sources project
  --permission-mode acceptEdits --allowedTools Bash
  --settings '{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true,"allowUnsandboxedCommands":false}}'
  --output-format stream-json --verbose)
if [ "${BASELINE}" -eq 0 ]; then
  CMD+=(--plugin-dir "${PLUGIN_DIR}")
fi

cd "${OUT_DIR}/work"
"${CMD[@]}" </dev/null >"${OUT_DIR}/transcript.jsonl"
echo "${OUT_DIR}"
