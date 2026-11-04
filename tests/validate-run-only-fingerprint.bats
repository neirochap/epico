#!/usr/bin/env bats
# validate-run.sh --only keeps an unselected PASS only on the code it passed on.
#
# Under --only, an unselected entry whose previous result is PASS is kept only
# when its recorded fingerprint equals the current one; on changed code it is
# run again, and so is an entry recorded with no fingerprint (a report written
# before fingerprints existed). SKIP and JUDGE entries are kept as before.
# The current fingerprint comes from `check-reuse.sh lookup`; when lookup is
# unusable (non-zero exit, no output, invalid JSON) the fingerprint is unknown
# and the entry is run again. Mode `off` and never-list commands still record
# their fingerprint, so they are kept on identical code like any other PASS.
#
# Hostile halves first: the code moved, or the record cannot say what code it
# saw — both must run again. Then the plain case: same code, kept untouched.
# The mode is the default (shadow): what is decided here is validate-run's own
# keep-or-run, never a reuse by the check runner.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  vr_story
  J="$STORY/.draft/validation-run.json"
  run --separate-stderr vr
  [ "$(counter c11)" -eq 1 ]
  [ "$(counter secrets)" -eq 1 ]
  touch "$OUTSIDE/fixed"
}

teardown() { reuse_teardown; }

# --- Must run again ---

@test "an edited tracked file: the unselected PASS entries run again; SKIP and JUDGE are kept" {
  old_fp=$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")
  is_hash "$old_fp"
  skip_before=$(entry 1.4); judge_before=$(entry 1.3)
  printf 'echo two\n' > "$PROJ/src/app.sh"
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 2 ]
  [ "$(counter secrets)" -eq 2 ]
  new_fp=$(fp_now)
  [ "$new_fp" != "$old_fp" ]
  [ "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")" = "$new_fp" ]
  [ "$(entry 1.2 | jq -r .result)" = PASS ]
  [ "$(entry 1.4)" = "$skip_before" ]
  [ "$(entry 1.3)" = "$judge_before" ]
}

@test "a new untracked file is a code change: the unselected PASS runs again" {
  printf 'echo new\n' > "$PROJ/src/new.sh"
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 2 ]
  [ "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")" = "$(fp_now)" ]
}

@test "an entry recorded with no fingerprint (a report from before fingerprints) runs again" {
  jq '.entries |= map(del(.fingerprint, .reused))' "$J" > "$J.tmp" && mv "$J.tmp" "$J"
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 2 ]
  is_hash "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")"
}

@test "an entry recorded with a null fingerprint runs again: null is no code at all" {
  jq '.entries |= map(if .id == "1.1" then .fingerprint = null else . end)' "$J" > "$J.tmp" && mv "$J.tmp" "$J"
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 2 ]
  [ "$(counter secrets)" -eq 1 ]
}

@test "an unusable lookup makes the current fingerprint unknown: the unselected PASS runs again" {
  # Fault injection on the producer only: a copy of scripts/ whose
  # check-reuse.sh fails `lookup` and hands every other subcommand to the real
  # script. git and the repository are untouched.
  mkdir -p "$WORK/plugin"
  cp -r "$PLUGIN_ROOT/scripts" "$WORK/plugin/scripts"
  mv "$WORK/plugin/scripts/check-reuse.sh" "$WORK/plugin/scripts/check-reuse-real.sh"
  cat > "$WORK/plugin/scripts/check-reuse.sh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = lookup ]; then printf '%s' "${LOOKUP_FAULT_OUTPUT-}"; exit "${LOOKUP_FAULT_CODE:-1}"; fi
exec bash "$(dirname "$0")/check-reuse-real.sh" "$@"
SH
  export LOOKUP_FAULT_CODE=1 LOOKUP_FAULT_OUTPUT=""
  run --separate-stderr bash "$WORK/plugin/scripts/validate-run.sh" --story "$STORY" --only 1.2
  [ "$(counter c11)" -eq 2 ]
  export LOOKUP_FAULT_CODE=0 LOOKUP_FAULT_OUTPUT="not json"
  run --separate-stderr bash "$WORK/plugin/scripts/validate-run.sh" --story "$STORY" --only 1.2
  [ "$(counter c11)" -eq 3 ]
  export LOOKUP_FAULT_CODE=0 LOOKUP_FAULT_OUTPUT=""
  run --separate-stderr bash "$WORK/plugin/scripts/validate-run.sh" --story "$STORY" --only 1.2
  [ "$(counter c11)" -eq 4 ]
}

# --- Must be kept ---

@test "same code: the unselected PASS is kept byte-identical, without running" {
  before=$(entry 1.1)
  run --separate-stderr vr --only 1.2
  [ "$(entry 1.2 | jq -r .result)" = PASS ]
  [ "$(counter c11)" -eq 1 ]
  [ "$(counter secrets)" -eq 1 ]
  [ "$(entry 1.1)" = "$before" ]
  is_hash "$(jq -r .fingerprint <<< "$before")"
  [ "$(jq -r .fingerprint <<< "$before")" = "$(fp_now)" ]
}

@test "editing only the story under .epico/ is not a code change: the PASS is kept" {
  # Fixing a Validation line in tasks.md is how a revalidation usually starts.
  printf '\n' >> "$STORY/tasks.md"
  printf 'notes\n' > "$STORY/notes.md"
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 1 ]
  is_hash "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")"
}

@test "mode off: an unselected PASS on identical code is kept, without running" {
  profile_mode off
  run --separate-stderr vr
  [ "$(counter c11)" -eq 2 ]
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 2 ]
  is_hash "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")"
  [ "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")" = "$(fp_now)" ]
}

@test "a never-list command: an unselected PASS on identical code is kept, without running" {
  write_profile '{"version": 1, "mode": "on", "tools": [], "inputs": [], "never": ["/c11"]}'
  run --separate-stderr vr
  [ "$(counter c11)" -eq 2 ]
  run --separate-stderr vr --only 1.2
  [ "$(counter c11)" -eq 2 ]
  is_hash "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")"
  [ "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")" = "$(fp_now)" ]
}
