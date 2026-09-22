#!/usr/bin/env bats
#
# Generic SKILL.md structural integrity across ALL plugins. Deterministic only —
# model-driven activation (does the model actually load the skill?) is
# skill-creator eval's job, not bats. Loops every plugins/*/skills/*, so new
# skills and new plugins are covered automatically.
# Plugin-specific skill rules (e.g. gox's paths glob) live under that plugin's
# own tests/ dir.

ROOT="$BATS_TEST_DIRNAME/.."

@test "every skill has parseable YAML with non-empty name and description strings" {
  run python3 - "$ROOT"/plugins/*/skills/*/SKILL.md <<'PY'
import sys
from pathlib import Path

import yaml

errors = []
for filename in sys.argv[1:]:
    try:
        lines = Path(filename).read_text(encoding="utf-8").splitlines()
        if not lines or lines[0] != "---":
            raise ValueError("missing YAML frontmatter")
        end = lines.index("---", 1)
        metadata = yaml.safe_load("\n".join(lines[1:end]))
        if not isinstance(metadata, dict):
            raise ValueError("frontmatter must be a mapping")
        for field in ("name", "description"):
            if not isinstance(metadata.get(field), str) or not metadata[field].strip():
                raise ValueError(f"{field} must be a non-empty string")
    except (OSError, ValueError, yaml.YAMLError) as exc:
        errors.append(f"{filename}: {exc}")
print("\n".join(errors))
sys.exit(bool(errors))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
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
