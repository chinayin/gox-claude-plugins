#!/usr/bin/env bash
# SessionStart thin nudge: push the model to use the team standards skills
# (no rule text here — the actual rules live in each skill's references/).
# fail-open: on any error, always exit 0, never exit 2 (exit 2 blocks the session).
set -u

# Missing jq -> silently fail-open
command -v jq >/dev/null 2>&1 || exit 0

MSG=$(cat <<'EOF'
[gox-code-rules] This repo follows team engineering standards, delivered as Claude Code skills (the rules live inside the skills, not here):
- Before writing or designing code, use the team standards skill that matches the current language/task. Go code; CLI flags; reading configuration, environment variables, or secrets; DB migrations; project scaffolding -> use the `gox-code-rules:go` skill. Consult it even for small/obvious-looking changes (e.g. reading one env var).
- Frontend code (React/Vue components, TypeScript/JavaScript, CSS/SCSS styling, state management, build/tooling config) -> use the `gox-code-rules:frontend` skill. Consult it even for small/obvious-looking changes (e.g. one prop or style tweak).
- Shell/bash scripts (.sh/.bash files, CLI/helper/CI scripts, flag parsing, stdout/stderr, exit codes) -> use the `gox-code-rules:shell` skill. Consult it even for small one-off scripts.
- For general engineering guidelines, see the `gox-code-rules:engineering` skill.
- The above is guidance; final enforcement is the repo's golangci-lint / CI / PR review.
EOF
)

jq -n --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
  || exit 0
exit 0
