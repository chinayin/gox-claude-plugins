# 各用例 checks.bats 共用的判分函数。EVAL_OUT 是 run-case.sh 的 <out-dir>。

eval_setup() {
  [ -n "${EVAL_OUT:-}" ] || skip "EVAL_OUT is not set; see evals/README.md"
  WORK="${EVAL_OUT}/work"
  TRANSCRIPT="${EVAL_OUT}/transcript.jsonl"
}

# 基线运行没有挂插件，技能加载类断言对它没有意义
require_plugin_run() {
  jq -e 'select(.type=="system" and .subtype=="init") | .skills | index("gox-code-rules:shell")' \
    "$TRANSCRIPT" >/dev/null || skip "baseline run: plugin not loaded"
}

# $1 = 技能裸名；模型在这次运行里是否加载过它
skill_loaded() {
  jq -e --arg re "(^|:)$1\$" \
    'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | select(.input.skill | test($re))' \
    "$TRANSCRIPT" >/dev/null
}

# $@ = 候选文件名；输出工作目录里第一个找到的路径
find_file() {
  local name hit
  for name in "$@"; do
    hit="$(find "$WORK" -name "$name" -type f -not -path '*/.git/*' | head -n 1)"
    if [ -n "$hit" ]; then
      echo "$hit"
      return 0
    fi
  done
  return 1
}

# $1 = 手写脚本；团队规定的脚本头
has_header() {
  [ "$(head -n 1 "$1")" = '#!/usr/bin/env bash' ] && grep -qE '^set -euo pipefail' "$1"
}

# $@ = 文件；源码里不出现 emoji 和颜色转义（中文注释不算）
no_emoji_or_color() {
  ! LC_ALL=C grep -nE $'\xf0\x9f|\xe2\x9c|\xe2\x9d|\xe2\x9a|\\\\(033|e|x1[bB])\\[|tput (setaf|bold)' "$@"
}

# $1 = bashly 项目目录；提交的产物与重新生成的结果逐字节一致
artifact_is_current() {
  local dir="$1" name copy
  command -v bashly >/dev/null 2>&1 || skip "bashly not installed"
  name="$(sed -n 's/^name:[[:space:]]*//p' "$dir/src/bashly.yml" | head -n 1)"
  copy="$BATS_TEST_TMPDIR/regen"
  cp -R "$dir" "$copy"
  (cd "$copy" && bashly generate --env production >/dev/null)
  cmp "$copy/$name" "$dir/$name"
}

# $1 = bashly 源目录；列出没带默认值就读取的可选 flag，每处一行。
# 必填或声明了 default 的 flag 一定有值，直接读不算问题。
unguarded_optional_flags() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

import yaml

src = Path(sys.argv[1])
root = src.parent  # import 的路径相对项目根目录
optional, always_set = set(), set()


def walk(cmd):
    for flag in cmd.get("flags") or []:
        if "import" in flag:
            flag = yaml.safe_load((root / flag["import"]).read_text())
        if not flag.get("long"):
            continue
        if flag.get("required") or "default" in flag:
            always_set.add(flag["long"])
        else:
            optional.add(flag["long"])
    for sub in cmd.get("commands") or []:
        walk(sub)


walk(yaml.safe_load((src / "bashly.yml").read_text()))
for path in sorted(src.rglob("*.sh")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for name in re.findall(r"\$\{args\[(--[a-z0-9-]+)\]\}", line):
            if name in optional - always_set:
                print(f"{path}:{number}: {line.strip()}")
PY
}
