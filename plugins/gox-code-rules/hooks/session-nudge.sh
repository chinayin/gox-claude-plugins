#!/usr/bin/env bash
# SessionStart 薄提示:推动模型使用团队规范技能(不含规则正文,正文在技能 references)。
# fail-open:任何错误一律 exit 0,绝不 exit 2(exit 2 会阻断会话)。
set -u

# 缺 jq → 静默 fail-open
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(cat <<'EOF'
[gox-code-rules] 本仓遵循团队工程规范(以 Claude Code 技能形式提供,规则正文在技能内,不在此处):
- 编写或设计代码前,使用与当前语言/任务匹配的团队规范技能。Go 代码/CLI/配置/迁移/脚手架 → 使用 `gox-code-rules:go` 技能。
- 通用工程准则见 `gox-code-rules:common` 技能。
- 以上为引导;最终强制以仓库的 golangci-lint / CI / PR review 为准。
EOF
)

jq -n --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
  || exit 0
exit 0
