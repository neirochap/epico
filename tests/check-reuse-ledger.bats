#!/usr/bin/env bats
# scripts/check-reuse.sh run: the ledger and the decision table.
#
# The ledger is <git-common-dir>/epico/reuse/ledger.json —
# {version: 1, entries: {key: {command, result, fingerprint, at, secs}}} —
# shared by every worktree of one repository, written through a temp file and
# a rename, capped at 2000 entries (oldest `at` dropped first). Only a PASS is
# ever a hit, and only in mode `on`. `off` runs and records nothing; `--fresh`
# runs and replaces; a command holding a `never` substring always runs and
# records nothing reusable. Both of those still REPORT the code fingerprint —
# they only write nothing. An unreadable ledger is set aside under a new
# timestamped name and the run proceeds as if it were empty; when it cannot
# even be set aside, the run still proceeds. A ledger that cannot be written
# changes neither the verdict nor the exit code.
#
# Every "it was not run" below is proved by a command with a side effect.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  L="$(ledger_dir)"
}

teardown() { reuse_teardown; }

entries_for() {  # <command> — how many ledger entries record this command
  if [ -f "$L/ledger.json" ]; then
    jq --arg c "$1" '[.entries[] | select(.command == $c)] | length' "$L/ledger.json"
  else echo 0; fi
}

set_aside_count() { find "$L" -maxdepth 1 -name 'ledger.json.unreadable-*' | wc -l | tr -d ' '; }

# --- Never a hit: what must run although the ledger knows the command ---

@test "mode on: a recorded FAIL is never reused" {
  profile_mode on
  c="$(bump f); exit 1"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 1 ]
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 1 ]
  [ "$(counter f)" -eq 2 ]
  jq -e '.decision == "ran" and .result == "FAIL"' <<< "$output"
  [ "$(entries_for "$c")" -eq 1 ]
  [ "$(jq -r --arg c "$c" '.entries[] | select(.command == $c) | .result' "$L/ledger.json")" = FAIL ]
}

@test "mode on: a command holding a never entry always runs and records nothing reusable" {
  profile_mode on '["needs-live-db"]'
  c="$(bump n) # needs-live-db"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran" and .result == "PASS"' <<< "$output"
  [ "$(counter n)" -eq 2 ]
  [ "$(entries_for "$c")" -eq 0 ]
}

@test "mode on: a never entry is a literal substring, not a pattern" {
  # `live.db` names those seven characters; `liveXdb` does not hold them, so
  # that command is reusable like any other.
  profile_mode on '["live.db"]'
  c="$(bump x) # liveXdb"
  run --separate-stderr cr run -- "$c"
  run --separate-stderr cr run -- "$c"
  jq -e '.decision == "reused"' <<< "$output"
  [ "$(counter x)" -eq 1 ]
}

@test "mode on: a PASS recorded before a code change is not reused after it" {
  profile_mode on
  c="$(bump code)"
  run --separate-stderr cr run -- "$c"
  printf 'echo two\n' > src/app.sh
  run --separate-stderr cr run -- "$c"
  jq -e '.decision == "ran"' <<< "$output"
  [ "$(counter code)" -eq 2 ]
}

@test "mode on: --fresh runs and replaces, and a FAIL it records outlives the old PASS" {
  profile_mode on
  c="$(bump fr); test ! -f '$OUTSIDE/broken'"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  run --separate-stderr cr run --fresh -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran"' <<< "$output"
  [ "$(counter fr)" -eq 2 ]
  [ "$(entries_for "$c")" -eq 1 ]
  # The world outside the key breaks; a fresh run records the FAIL in place of
  # the PASS, and the next plain run must not find the PASS again.
  touch "$OUTSIDE/broken"
  run --separate-stderr cr run --fresh -- "$c"
  [ "$status" -eq 1 ]
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 1 ]
  jq -e '.decision == "ran" and .result == "FAIL"' <<< "$output"
  [ "$(counter fr)" -eq 4 ]
  [ "$(entries_for "$c")" -eq 1 ]
}

@test "mode off: every run runs, and nothing is recorded" {
  profile_mode off
  c="$(bump off)"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.mode == "off" and .decision == "ran"' <<< "$output"
  [ "$(counter off)" -eq 2 ]
  [ ! -e "$L/ledger.json" ]
  [ ! -e "$L/shadow.log" ]
}

@test "another repository with the same content never sees this repository's ledger" {
  profile_mode on
  git add -f .epico/reuse-profile.json && commit_all "track the profile"
  c="$(bump other)"
  run --separate-stderr cr run -- "$c"
  git clone -q "$PROJ" "$WORK/clone"
  cd "$WORK/clone"
  run --separate-stderr cr run -- "$c"
  jq -e '.decision == "ran"' <<< "$output"
  [ "$(counter other)" -eq 2 ]
}

@test "mode off and a never-list command still report the fingerprint, and write nothing" {
  profile_mode off
  run --separate-stderr cr run -- "$(bump off2)"
  [ "$status" -eq 0 ]
  is_hash "$(jq -r .fingerprint <<< "$output")"
  [ "$(jq -r .fingerprint <<< "$output")" = "$(fp_now)" ]
  [ ! -e "$L/ledger.json" ]
  profile_mode on '["needs-live-db"]'
  c="$(bump never2) # needs-live-db"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  is_hash "$(jq -r .fingerprint <<< "$output")"
  [ "$(entries_for "$c")" -eq 0 ]
  [ "$(counter off2)" -eq 1 ]
  [ "$(counter never2)" -eq 1 ]
}

# --- The hit ---

@test "mode on: a PASS on the same command, code and environment is reused without running" {
  profile_mode on
  c="$(bump hit)"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran"' <<< "$output"
  first=$output
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.decision == "reused" and .result == "PASS" and .would_reuse == true and .exit == 0' <<< "$output"
  [ "$(counter hit)" -eq 1 ]
  [ "$(jq -r .key <<< "$output")" = "$(jq -r .key <<< "$first")" ]
}

@test "the ledger entry records what ran, under the key the run reported" {
  profile_mode on
  c="$(bump rec)"
  run --separate-stderr cr run -- "$c"
  k=$(jq -r .key <<< "$output"); f=$(jq -r .fingerprint <<< "$output")
  is_hash "$k"
  jq -e '.version == 1 and (.entries | type) == "object"' "$L/ledger.json"
  jq -e --arg k "$k" --arg c "$c" --arg f "$f" '.entries[$k] | .command == $c and .result == "PASS" and .fingerprint == $f and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")) and (.secs | type) == "number"' "$L/ledger.json"
}

@test "a PASS recorded in the main worktree is reused in a linked worktree, from one shared ledger" {
  profile_mode on
  git add -f .epico/reuse-profile.json && commit_all "track the profile"
  c="$(bump wt)"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  git worktree add -q "$WORK/linked" HEAD
  cd "$WORK/linked"
  [ "$(ledger_dir "$WORK/linked")" = "$L" ]
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.decision == "reused"' <<< "$output"
  [ "$(counter wt)" -eq 1 ]
  [ -z "$(find "$PROJ/.git/worktrees" -name ledger.json)" ]
}

# --- An unreadable ledger is set aside, never trusted, never lost ---

@test "an unknown-version ledger holding a PASS for this very key is not trusted" {
  profile_mode on
  c="$(bump ver)"
  k=$(key_of "$c")
  is_hash "$k"
  mkdir -p "$L"
  jq -n --arg k "$k" --arg c "$c" '{version: 2, entries: {($k): {command: $c, result: "PASS", fingerprint: "x", at: "2026-01-01T00:00:00Z", secs: 1}}}' > "$L/ledger.json"
  cp "$L/ledger.json" "$WORK/ledger.v2"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran"' <<< "$output"
  [ "$(counter ver)" -eq 1 ]
  [ "$(set_aside_count)" -eq 1 ]
  cmp -s "$WORK/ledger.v2" "$(find "$L" -maxdepth 1 -name 'ledger.json.unreadable-*')"
  jq -e '.version == 1' "$L/ledger.json"
}

@test "two corrupt ledgers in a row: two set-aside copies, the first never replaced" {
  profile_mode on
  mkdir -p "$L"
  printf 'first-garbage{' > "$L/ledger.json"
  run --separate-stderr cr run -- "$(bump c1)"
  [ "$status" -eq 0 ]
  [ "$(counter c1)" -eq 1 ]
  printf 'second-garbage{' > "$L/ledger.json"
  run --separate-stderr cr run -- "$(bump c2)"
  [ "$status" -eq 0 ]
  [ "$(counter c2)" -eq 1 ]
  [ "$(set_aside_count)" -eq 2 ]
  [ "$(grep -l 'first-garbage' "$L"/ledger.json.unreadable-* | wc -l)" -eq 1 ]
  [ "$(grep -l 'second-garbage' "$L"/ledger.json.unreadable-* | wc -l)" -eq 1 ]
  jq -e '.version == 1 and (.entries | type) == "object"' "$L/ledger.json"
}

@test "a ledger of the wrong shape is set aside and the check runs" {
  profile_mode on
  mkdir -p "$L"
  printf '{"version": 1, "entries": []}\n' > "$L/ledger.json"
  run --separate-stderr cr run -- "$(bump shape)"
  [ "$status" -eq 0 ]
  [ "$(counter shape)" -eq 1 ]
  [ "$(set_aside_count)" -eq 1 ]
  jq -e '(.entries | type) == "object"' "$L/ledger.json"
}

@test "no ledger yet: the check runs, a version-1 ledger appears, nothing is set aside" {
  profile_mode on
  [ ! -e "$L/ledger.json" ]
  run --separate-stderr cr run -- "$(bump first)"
  [ "$status" -eq 0 ]
  [ "$(counter first)" -eq 1 ]
  jq -e '.version == 1' "$L/ledger.json"
  [ "$(set_aside_count)" -eq 0 ]
}

# --- A failed save never changes the verdict ---

@test "a ledger that cannot be written: same verdict, same exit code, and a warning" {
  if [ "$(id -u)" -eq 0 ]; then skip "root writes a read-only directory"; fi
  profile_mode on
  mkdir -p "$L"
  printf '{"version": 1, "entries": {}}\n' > "$L/ledger.json"
  chmod 444 "$L/ledger.json"
  chmod 555 "$L"
  run --separate-stderr cr run -- "$(bump ro); exit 0"
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .decision == "ran"' <<< "$output"
  [[ "$stderr" == *record* ]]
  run --separate-stderr cr run -- "$(bump ro); exit 1"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL"' <<< "$output"
  [[ "$stderr" == *record* ]]
  [ "$(counter ro)" -eq 2 ]
  chmod 755 "$L"
}

@test "an unreadable ledger in a read-only directory: the check still runs, verdict and exit kept, a warning" {
  if [ "$(id -u)" -eq 0 ]; then skip "root writes a read-only directory"; fi
  profile_mode on
  mkdir -p "$L"
  printf 'garbage{' > "$L/ledger.json"
  chmod 555 "$L"
  run --separate-stderr cr run -- "$(bump rog); exit 0"
  [ "$status" -eq 0 ]
  [ "$(counter rog)" -eq 1 ]
  jq -e '.result == "PASS" and .decision == "ran"' <<< "$output"
  [ -n "$stderr" ]
  run --separate-stderr cr run -- "$(bump rog); exit 1"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL"' <<< "$output"
  [ "$(counter rog)" -eq 2 ]
  chmod 755 "$L"
  [ "$(cat "$L/ledger.json")" = 'garbage{' ]
}

# --- Bounds and the write path ---

@test "the ledger is capped at 2000 entries, dropping the oldest at first — not the first inserted" {
  profile_mode on
  mkdir -p "$L"
  # k1000 holds the oldest `at` and sits in the middle of the insertion order.
  jq -n '{version: 1, entries: ([range(2000)] | map({key: "k\(.)", value: {command: "c\(.)", result: "PASS", fingerprint: "f", secs: 0,
    at: (if . == 1000 then "2020-01-01T00:00:00Z" else "2025-06-01T00:00:00Z" end)}}) | from_entries)}' > "$L/ledger.json"
  run --separate-stderr cr run -- "$(bump cap)"
  [ "$status" -eq 0 ]
  k=$(jq -r .key <<< "$output")
  is_hash "$k"
  [ "$(jq '.entries | length' "$L/ledger.json")" -eq 2000 ]
  jq -e --arg k "$k" '.entries | has($k)' "$L/ledger.json"
  jq -e '.entries | has("k1000") | not' "$L/ledger.json"
  jq -e '.entries | has("k0") and has("k1999")' "$L/ledger.json"
}

@test "no temp file is left in the ledger directory after runs" {
  profile_mode on
  run --separate-stderr cr run -- "true"
  run --separate-stderr cr run -- "false"
  run --separate-stderr cr run --fresh -- "true"
  [ -f "$L/ledger.json" ]
  [ "$(find "$L" -maxdepth 1 -type f ! -name ledger.json ! -name shadow.log | wc -l | tr -d ' ')" -eq 0 ]
}
