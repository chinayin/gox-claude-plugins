#!/usr/bin/env bats
#
# Structural integrity of the SKILL.md files and their references/ index.
# These are deterministic checks — they do NOT test model-driven activation
# (that is the job of skill-creator eval). They guard the realistic regression:
# a SKILL.md index and its references/ files drifting out of sync. The checks
# loop over every skill, so new skills are covered automatically.

SKILLS_DIR="plugins/gox-code-rules/skills"

@test "every skill has name + description frontmatter" {
  for d in "$SKILLS_DIR"/*/; do
    s="${d}SKILL.md"
    grep -qE '^name:[[:space:]]*\S' "$s"        || { echo "missing name: $s"; false; }
    grep -qE '^description:[[:space:]]*\S' "$s"  || { echo "missing description: $s"; false; }
  done
}

@test "language skills (go, frontend, shell) declare a non-empty paths glob" {
  for name in go frontend shell; do
    grep -qE '^paths:[[:space:]]*\S' "$SKILLS_DIR/$name/SKILL.md" \
      || { echo "missing paths: $name"; false; }
  done
}

@test "no orphan references — every references/*.md is indexed in its SKILL.md" {
  for d in "$SKILLS_DIR"/*/; do
    [ -d "${d}references" ] || continue
    for f in "${d}references"/*.md; do
      base="$(basename "$f")"
      grep -q "references/$base" "${d}SKILL.md" \
        || { echo "orphan reference not indexed: $f"; false; }
    done
  done
}

@test "no dangling links — every references/X.md mentioned in a SKILL.md exists" {
  for d in "$SKILLS_DIR"/*/; do
    for ref in $(grep -oE 'references/[A-Za-z0-9._-]+\.md' "${d}SKILL.md" 2>/dev/null | sort -u); do
      [ -f "${d}${ref}" ] || { echo "dangling link in ${d}SKILL.md: $ref"; false; }
    done
  done
}
