#!/usr/bin/env bats
#
# gox-code-rules specific: the file-bound skills must declare a paths glob as metadata.
# Actual activation is driven by the description and session nudge. (Description-only skills like
# `engineering` intentionally have no paths and are not checked here.)

SK="$BATS_TEST_DIRNAME/../skills"

@test "file-bound skills (go, frontend, shell, skill) declare a non-empty paths glob" {
  for name in go frontend shell skill; do
    grep -qE '^paths:[[:space:]]*\S' "$SK/$name/SKILL.md" \
      || { echo "missing paths: $name"; false; }
  done
}
