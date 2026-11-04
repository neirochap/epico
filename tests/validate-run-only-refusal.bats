#!/usr/bin/env bats
# validate-run.sh --only needs a previous full run.
#
# A revalidation of named entries keeps every other entry of the previous run.
# With no previous run there is nothing to keep, and a report built from the
# named entries alone would pass a story on a fraction of its checks. So --only
# with no .draft/validation-run.json refuses: exit 2, no report written, no
# command run, and the message names a full run as the first step.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  vr_story
}

teardown() { reuse_teardown; }

@test "--only with no previous run: exit 2, no JSON, no report, no command run" {
  run --separate-stderr vr --only 1.1
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ ! -e "$STORY/.draft/validation-run.json" ]
  [ ! -e "$STORY/.draft/validation-report.yaml" ]
  [ "$(counter c11)" -eq 0 ]
}

@test "--only with no previous run: the message names a full run first" {
  run --separate-stderr vr --only 1.1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--only"* ]]
  [[ "$stderr" == *"without --only"* || "$stderr" == *"full run"* ]]
}

@test "a leftover report with no run JSON is still refused, and left byte-identical" {
  # The refusal keys on the run itself, never on the YAML a reader may have
  # left behind: only validation-run.json holds the entries --only would keep.
  mkdir -p "$STORY/.draft"
  printf 'story: "007-shelf"\nverdict: pass\nresults:\ngates:\n' > "$STORY/.draft/validation-report.yaml"
  cp "$STORY/.draft/validation-report.yaml" "$WORK/yaml.before"
  run --separate-stderr vr --only 1.1,gate:Secrets
  [ "$status" -eq 2 ]
  cmp -s "$WORK/yaml.before" "$STORY/.draft/validation-report.yaml"
  [ ! -e "$STORY/.draft/validation-run.json" ]
  [ "$(counter c11)" -eq 0 ]
  [ "$(counter secrets)" -eq 0 ]
}

@test "after a full run, --only proceeds: the refusal is for the missing run alone" {
  run --separate-stderr vr --only 1.1
  [ "$status" -eq 2 ]
  run --separate-stderr vr
  [ "$status" -eq 1 ]
  [ -f "$STORY/.draft/validation-run.json" ]
  touch "$OUTSIDE/fixed"
  run --separate-stderr vr --only 1.2
  [ "$status" -ne 2 ]
  [ "$(jq -r '.entries[] | select(.id == "1.2") | .result' "$STORY/.draft/validation-run.json")" = PASS ]
}
