#!/usr/bin/env bats
#
# Generic SKILL.md structural integrity across ALL plugins. Deterministic only —
# model-driven activation (does the model actually load the skill?) is
# skill-creator eval's job, not bats. Loops every plugins/*/skills/*, so new
# skills and new plugins are covered automatically.
# Plugin-specific skill rules (e.g. gox's paths glob) live under that plugin's
# own tests/ dir.

ROOT="$BATS_TEST_DIRNAME/.."

@test "every skill has name + description frontmatter" {
  for s in "$ROOT"/plugins/*/skills/*/SKILL.md; do
    [ -e "$s" ] || continue
    grep -qE '^name:[[:space:]]*\S' "$s"        || { echo "missing name: $s"; false; }
    grep -qE '^description:[[:space:]]*\S' "$s"  || { echo "missing description: $s"; false; }
  done
}

@test "no orphan references — every references/*.md is indexed in its SKILL.md" {
  for d in "$ROOT"/plugins/*/skills/*/; do
    [ -d "${d}references" ] || continue
    for f in "${d}references"/*.md; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      grep -q "references/$base" "${d}SKILL.md" \
        || { echo "orphan reference not indexed: $f"; false; }
    done
  done
}

@test "no dangling links — every references/X.md mentioned in a skill doc exists" {
  # 覆盖 SKILL.md 与 references/ 内文件的互引;引用统一写作 references/X.md,
  # 相对技能根目录(references 内文件取其上一级为根)。
  for s in "$ROOT"/plugins/*/skills/*/SKILL.md "$ROOT"/plugins/*/skills/*/references/*.md; do
    [ -e "$s" ] || continue
    d="$(dirname "$s")/"
    case "$s" in */references/*) d="$(dirname "$(dirname "$s")")/";; esac
    for ref in $(grep -oE 'references/[A-Za-z0-9._-]+\.md' "$s" 2>/dev/null | sort -u); do
      [ -f "${d}${ref}" ] || { echo "dangling link in $s: $ref"; false; }
    done
  done
}
