#!/usr/bin/env bats
# validate-run.sh settles each runnable entry through check-reuse.sh run.
#
# Every entry of validation-run.json gains `reused` (bool) and `fingerprint`
# (string|null); kind, id, result, qualifier and detail are unchanged. The YAML
# report gains `reused:` on each result and gate. In mode `on` a PASS on
# unchanged code is reused instead of run — but what validate-run checks
# itself (the Tests path, the Commit in git log) is still checked. `--fresh`
# and `--timeout` pass through.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  vr_story
  J="$STORY/.draft/validation-run.json"
  Y="$STORY/.draft/validation-report.yaml"
}

teardown() { reuse_teardown; }

# --- Hostile halves: a reused PASS settles the command, never the rest ---

@test "mode on: a reused PASS still fails on a missing test file" {
  profile_mode on
  run --separate-stderr vr
  [ "$(counter c16)" -eq 1 ]
  run --separate-stderr vr
  [ "$(counter c16)" -eq 1 ]
  jq -e '.entries[] | select(.id == "1.6") | .reused == true and .result == "FAIL" and (.detail | test("test file missing"))' "$J"
}

@test "mode on: a FAIL is never reused, and runs again on the next validation" {
  profile_mode on
  run --separate-stderr vr
  run --separate-stderr vr
  jq -e '.entries[] | select(.id == "1.2") | .result == "FAIL" and .reused == false' "$J"
}

@test "mode on: --fresh passes through and runs every command again" {
  profile_mode on
  run --separate-stderr vr
  run --separate-stderr vr --fresh
  [ "$(counter c11)" -eq 2 ]
  [ "$(counter secrets)" -eq 2 ]
  jq -e '[.entries[] | select(.id == "1.1" or (.id | startswith("Secrets")))] | length == 2 and all(.reused == false)' "$J"
}

# --- The reuse itself ---

@test "mode on: an unchanged PASS is reused on the next validation, without running" {
  profile_mode on
  run --separate-stderr vr
  [ "$(counter c11)" -eq 1 ]
  jq -e '.entries[] | select(.id == "1.1") | .reused == false' "$J"
  run --separate-stderr vr
  [ "$(counter c11)" -eq 1 ]
  [ "$(counter secrets)" -eq 1 ]
  jq -e '.entries[] | select(.id == "1.1") | .reused == true and .result == "PASS"' "$J"
  jq -e '.entries[] | select(.id | startswith("Secrets")) | .reused == true and .result == "PASS"' "$J"
}

@test "shadow (the default): every validation runs every command, reused stays false" {
  run --separate-stderr vr
  run --separate-stderr vr
  [ "$(counter c11)" -eq 2 ]
  jq -e '[.entries[] | .reused] | all(. == false)' "$J"
}

# --- The report shape: additive only ---

@test "every entry gains reused (bool) and fingerprint (string|null); the run ones carry this code's fingerprint" {
  run --separate-stderr vr
  [ "$status" -eq 1 ]
  jq -e '.entries | length > 0 and all(has("reused") and (.reused | type) == "boolean" and has("fingerprint") and ((.fingerprint | type) == "string" or .fingerprint == null))' "$J"
  now=$(fp_now)
  is_hash "$now"
  for id in 1.1 1.2 1.6; do
    [ "$(jq -r --arg i "$id" '.entries[] | select(.id == $i) | .fingerprint' "$J")" = "$now" ]
  done
}

@test "the fields a reader relies on are unchanged" {
  run --separate-stderr vr
  [ "$status" -eq 1 ]
  jq -e '.story == "007-shelf" and .generated_by == "epico-validate-run" and .verdict == "fail"' "$J"
  jq -e '.entries[] | select(.id == "1.1") | .kind == "sub" and .result == "PASS" and .qualifier == null and (.detail | startswith("`echo ran >> ")) and (.detail | test("exit 0"))' "$J"
  jq -e '.entries[] | select(.id == "1.2") | .result == "FAIL" and (.detail | test("exit 1"))' "$J"
  jq -e '.entries[] | select(.id == "1.3") | .result == "JUDGE"' "$J"
  jq -e '.entries[] | select(.id == "1.4") | .result == "SKIP" and .qualifier == "deferred"' "$J"
  jq -e '.entries[] | select(.id | startswith("Secrets")) | .kind == "gate" and .result == "PASS"' "$J"
  jq -e '.entries[] | select(.id | startswith("All task validations")) | .result == "FAIL"' "$J"
  jq -e '(keys | sort) == ["entries", "generated_at", "generated_by", "story", "verdict"]' "$J"
  # Exactly the five old fields plus the two new ones, on every entry.
  jq -e 'all(.entries[]; (keys | sort) == ["detail", "fingerprint", "id", "kind", "qualifier", "result", "reused"])' "$J"
}

@test "the YAML report carries reused: on each result and each gate" {
  run --separate-stderr vr
  n=$(jq '.entries | length' "$J")
  [ "$n" -gt 0 ]
  [ "$(grep -cE '^    reused: (true|false)$' "$Y")" -eq "$n" ]
  grep -q '^verdict: fail$' "$Y"
  grep -q '^    qualifier: "deferred"$' "$Y"
  run bash "$PLUGIN_ROOT/scripts/report.sh" --story "$STORY"
  [ "$(jq -r .validation.verdict <<< "$output")" = fail ]
}

@test "--timeout passes through: a hanging command fails at its timeout" {
  sed -i "s|\`echo ran >> $OUTSIDE/c11\`|\`sleep 10\`|" "$STORY/tasks.md"
  SECONDS=0
  run --separate-stderr vr --timeout 1
  [ "$SECONDS" -lt 15 ]
  jq -e '.entries[] | select(.id == "1.1") | .result == "FAIL" and (.detail | test("timed out after 1s"))' "$J"
  jq -e '.entries[] | select(.id == "1.1") | has("reused")' "$J"
}

@test "usage: an unknown flag is refused with exit 2, and --fresh is not one" {
  run --separate-stderr vr --no-such-flag
  [ "$status" -eq 2 ]
  run --separate-stderr vr --fresh
  [ "$status" -ne 2 ]
  [ -f "$J" ]
}
