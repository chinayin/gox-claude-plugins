#!/usr/bin/env bats
#
# Structural integrity of the SKILL.md files and their references/ index.
# These are deterministic checks — they do NOT test model-driven activation
# (that is the job of skill-creator eval). They guard the realistic regression:
# the SKILL.md index and the references/ files drifting out of sync.

GO_SKILL="plugins/gox-code-rules/skills/go/SKILL.md"
GO_REFS="plugins/gox-code-rules/skills/go/references"
ENG_SKILL="plugins/gox-code-rules/skills/engineering/SKILL.md"

@test "go SKILL.md has required frontmatter: name, description, paths" {
  grep -qE '^name:[[:space:]]*go[[:space:]]*$' "$GO_SKILL"
  grep -qE '^description:[[:space:]]*\S' "$GO_SKILL"
  grep -qE '^paths:[[:space:]]*\S' "$GO_SKILL"
}

@test "engineering SKILL.md has required frontmatter: name, description" {
  grep -qE '^name:[[:space:]]*engineering[[:space:]]*$' "$ENG_SKILL"
  grep -qE '^description:[[:space:]]*\S' "$ENG_SKILL"
}

@test "every references/*.md is mentioned in the go SKILL.md index (no orphan)" {
  for f in "$GO_REFS"/*.md; do
    base="$(basename "$f")"
    grep -q "references/$base" "$GO_SKILL" \
      || { echo "orphan reference not indexed: $base"; false; }
  done
}

@test "every references/X.md mentioned in go SKILL.md exists (no dangling link)" {
  for ref in $(grep -oE 'references/[A-Za-z0-9._-]+\.md' "$GO_SKILL" | sort -u); do
    [ -f "$GO_REFS/$(basename "$ref")" ] \
      || { echo "dangling link in SKILL.md: $ref"; false; }
  done
}
