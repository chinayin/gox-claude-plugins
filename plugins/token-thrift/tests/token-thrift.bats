#!/usr/bin/env bats
#
# token-thrift specific: the subagent definitions are well-formed and the
# delegate skill only names agents that actually exist. Deterministic only —
# whether the model actually delegates to these agents (or loads the skill) is a
# skill-creator eval concern, not something bats can assert.

PLUGIN="$BATS_TEST_DIRNAME/.."

@test "each agent has name/description/tools frontmatter and a valid model" {
  for a in "$PLUGIN"/agents/*.md; do
    grep -qE '^name:[[:space:]]*\S' "$a"        || { echo "missing name: $a"; false; }
    grep -qE '^description:[[:space:]]*\S' "$a"  || { echo "missing description: $a"; false; }
    grep -qE '^tools:[[:space:]]*\S' "$a"        || { echo "missing tools: $a"; false; }
    model="$(grep -E '^model:[[:space:]]*' "$a" | head -1 | sed -E 's/^model:[[:space:]]*//' | tr -d '[:space:]')"
    case "$model" in
      haiku|sonnet|opus|inherit) ;;
      *) echo "bad or missing model in $a: '$model'"; false ;;
    esac
  done
}

@test "each agent's name frontmatter matches its filename" {
  for a in "$PLUGIN"/agents/*.md; do
    fname="$(basename "$a" .md)"
    name="$(grep -E '^name:[[:space:]]*' "$a" | head -1 | sed -E 's/^name:[[:space:]]*//' | tr -d '[:space:]')"
    [ "$name" = "$fname" ] || { echo "name/file mismatch in $a: '$name' vs '$fname'"; false; }
  done
}

@test "delegate skill references only agents that exist" {
  skill="$PLUGIN/skills/delegate/SKILL.md"
  [ -f "$skill" ] || { echo "delegate SKILL.md missing"; false; }
  for ag in cheap-reader careful-writer; do
    grep -q "$ag" "$skill" || { echo "delegate skill does not mention: $ag"; false; }
    [ -f "$PLUGIN/agents/$ag.md" ] || { echo "skill names a missing agent: $ag"; false; }
  done
}
