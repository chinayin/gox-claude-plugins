#!/usr/bin/env bats
#
# gox-code-rules specific: the language skills must declare a paths glob so they
# auto-activate when you edit the matching files. (Description-only skills like
# `engineering` intentionally have no paths and are not checked here.)

SK="$BATS_TEST_DIRNAME/../skills"

@test "language skills (go, frontend, shell) declare a non-empty paths glob" {
  for name in go frontend shell; do
    grep -qE '^paths:[[:space:]]*\S' "$SK/$name/SKILL.md" \
      || { echo "missing paths: $name"; false; }
  done
}
