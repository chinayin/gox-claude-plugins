#!/usr/bin/env bats
#
# evals/ 下两个评估脚本的确定性测试：用桩 claude 代替真实模型，
# 只验证参数处理和调用方式。真实评估是手动的，见 evals/README.md。

setup() {
  EVALS="$BATS_TEST_DIRNAME/evals"
  CASE="$EVALS/bashly/add-command"
  OUT="$BATS_TEST_TMPDIR/out"
  # 桩：把收到的参数逐行记下，再吐出预设的事件流
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGS"
cat "${STUB_STREAM:-/dev/null}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  export STUB_ARGS="$BATS_TEST_TMPDIR/args"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

skill_event() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"gox-code-rules:%s"}}]}}\n' "$1"
}

@test "run-case: unknown option exits 1" {
  run bash "$EVALS/run-case.sh" --nope "$CASE" "$OUT"
  [ "$status" -eq 1 ]
  [ ! -e "$OUT" ]
}

@test "run-case: a case without prompt.md exits 2" {
  run bash "$EVALS/run-case.sh" "$BATS_TEST_TMPDIR" "$OUT"
  [ "$status" -eq 2 ]
}

@test "run-case: refuses an existing out dir" {
  mkdir "$OUT"
  run bash "$EVALS/run-case.sh" "$CASE" "$OUT"
  [ "$status" -eq 1 ]
}

@test "run-case: runs sonnet with the plugin, isolated from user settings, in a copy of the fixture" {
  run bash "$EVALS/run-case.sh" "$CASE" "$OUT"
  [ "$status" -eq 0 ]
  [ -f "$OUT/work/src/bashly.yml" ]
  [ -f "$OUT/transcript.jsonl" ]
  grep -qx 'sonnet' "$STUB_ARGS"
  grep -qx -- '--plugin-dir' "$STUB_ARGS"
  grep -A1 -x -- '--setting-sources' "$STUB_ARGS" | grep -qx 'project'
  grep -q '"sandbox"' "$STUB_ARGS"
}

@test "run-case: --baseline leaves the plugin out; EVAL_MODEL overrides the model" {
  EVAL_MODEL=haiku run bash "$EVALS/run-case.sh" --baseline "$CASE" "$OUT"
  [ "$status" -eq 0 ]
  grep -qx 'haiku' "$STUB_ARGS"
  run grep -x -- '--plugin-dir' "$STUB_ARGS"
  [ "$status" -ne 0 ]
}

@test "run-trigger: a loaded skill that matches the expectation passes" {
  skill_event shell >"$BATS_TEST_TMPDIR/stream"
  printf 'shell\t-\twrite a script\n' >"$BATS_TEST_TMPDIR/q.tsv"
  STUB_STREAM="$BATS_TEST_TMPDIR/stream" run bash "$EVALS/run-trigger.sh" --runs 1 "$BATS_TEST_TMPDIR/q.tsv"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[PASS]"$'\t'"shell"$'\t'"shell"$'\t'* ]]
  [ "${lines[1]}" = "result: PASS=1 FAIL=0" ]
}

@test "run-trigger: bashly loading for a plain shell query fails the row and the run" {
  { skill_event shell; skill_event bashly; } >"$BATS_TEST_TMPDIR/stream"
  printf 'shell\t-\twrite a script\n' >"$BATS_TEST_TMPDIR/q.tsv"
  STUB_STREAM="$BATS_TEST_TMPDIR/stream" run bash "$EVALS/run-trigger.sh" --runs 1 "$BATS_TEST_TMPDIR/q.tsv"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "[FAIL]"$'\t'"shell"$'\t'"bashly,shell"$'\t'* ]]
}

@test "run-trigger: no skill loaded reports none" {
  printf 'none\t-\texplain pipefail\n' >"$BATS_TEST_TMPDIR/q.tsv"
  run bash "$EVALS/run-trigger.sh" --runs 1 "$BATS_TEST_TMPDIR/q.tsv"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[PASS]"$'\t'"none"$'\t'"none"$'\t'* ]]
}

@test "run-trigger: an unknown expect value or a missing file is rejected" {
  printf 'maybe\t-\twrite a script\n' >"$BATS_TEST_TMPDIR/q.tsv"
  run bash "$EVALS/run-trigger.sh" "$BATS_TEST_TMPDIR/q.tsv"
  [ "$status" -eq 1 ]
  run bash "$EVALS/run-trigger.sh" "$BATS_TEST_TMPDIR/nope.tsv"
  [ "$status" -eq 2 ]
}

@test "every eval case has a prompt and checks; every trigger row is well-formed" {
  for d in "$EVALS"/*/*/; do
    [ -s "${d}prompt.md" ] || { echo "missing prompt: $d"; false; }
    [ -s "${d}checks.bats" ] || { echo "missing checks: $d"; false; }
  done
  for f in "$EVALS"/*/triggers.tsv; do
    run awk -F'\t' 'NF != 3 || $1 !~ /^(shell|bashly|none)$/ { print FILENAME ": " $0; bad = 1 } END { exit bad }' "$f"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
}
