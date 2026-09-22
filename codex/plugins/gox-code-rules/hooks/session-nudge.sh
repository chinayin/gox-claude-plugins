#!/usr/bin/env bash
# Codex 提醒只提供包内技能路径；依赖缺失时不阻断会话。
set -u
EVENT="${1:-SessionStart}"
case "$EVENT" in SessionStart|SubagentStart) ;; *) exit 0 ;; esac
ROOT="${PLUGIN_ROOT:-}"
[ -n "$ROOT" ] && [ -d "$ROOT/skills" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

if [ "$EVENT" = SubagentStart ]; then
  INTRO='Follow the standards already included in your brief. Read a skill only if the brief supplies none and your task requires writing code.'
else
  INTRO='Before writing or designing code, read the applicable SKILL.md below, usually one. Read its references only as needed. Do not reload standards already read in this session. Include applicable standards in briefs for agents that will edit code.'
fi
MSG=$(cat <<EOF
[gox-code-rules] $INTRO
- Go, CLI configuration or DB migrations: \`$ROOT/skills/go/SKILL.md\`.
- Shell scripts: \`$ROOT/skills/shell/SKILL.md\`.
- Writing agent skills: \`$ROOT/skills/skill/SKILL.md\`.
- Multi-file design or refactoring: \`$ROOT/skills/engineering/SKILL.md\`; skip for a one-file edit.
Use the available file-reading tool. These are guidance; lint and CI remain necessary.
EOF
)
jq -n --arg ev "$EVENT" --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}' || exit 0
exit 0
