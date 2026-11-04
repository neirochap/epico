#!/usr/bin/env bats
# scripts/check-reuse.sh: shadow mode and `stats`.
#
# Shadow is the default mode, also with no profile: every check runs, and each
# run appends one line {at, command, key, would_reuse, result, secs} to
# <git-common-dir>/epico/reuse/shadow.log, capped at 5000 lines (oldest
# first out). `stats` summarises it: runs, would_reuse, agreed, secs_reusable,
# and every disagreement — a run that would have reused a PASS and failed — with
# its command and time. A shadow line that cannot be written changes neither
# the verdict nor the exit code, and says so on stderr.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  L="$(ledger_dir)"
}

teardown() { reuse_teardown; }

log_lines() { if [ -f "$L/shadow.log" ]; then wc -l < "$L/shadow.log" | tr -d ' '; else echo 0; fi; }

# --- Hostile halves: what must not read as reusable, and what must not be logged ---

@test "shadow: a recorded FAIL never makes the next run would_reuse" {
  c="$(bump f); exit 1"
  run --separate-stderr cr run -- "$c"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 1 ]
  jq -e '.would_reuse == false and .decision == "ran"' <<< "$output"
  [ "$(counter f)" -eq 2 ]
  [ "$(log_lines)" -eq 2 ]
  [ "$(jq -s '[.[] | select(.would_reuse)] | length' "$L/shadow.log")" -eq 0 ]
}

@test "modes on and off append no shadow line" {
  profile_mode on
  run --separate-stderr cr run -- "$(bump on)"
  run --separate-stderr cr run -- "$(bump on)"
  [ "$(log_lines)" -eq 0 ]
  profile_mode off
  run --separate-stderr cr run -- "$(bump off)"
  [ "$status" -eq 0 ]
  jq -e '.mode == "off"' <<< "$output"
  [ "$(log_lines)" -eq 0 ]
}

# --- Shadow runs everything and measures ---

@test "no profile: shadow runs every check, and the second run would have been reused" {
  [ ! -e .epico/reuse-profile.json ]
  c="$(bump s)"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow" and .decision == "ran" and .would_reuse == false' <<< "$output"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow" and .decision == "ran" and .would_reuse == true' <<< "$output"
  [ "$(counter s)" -eq 2 ]
}

@test "an explicit shadow profile behaves as the default" {
  profile_mode shadow
  c="$(bump s2)"
  run --separate-stderr cr run -- "$c"
  run --separate-stderr cr run -- "$c"
  jq -e '.decision == "ran" and .would_reuse == true' <<< "$output"
  [ "$(counter s2)" -eq 2 ]
}

@test "each shadow run appends one line with the six fields" {
  c="$(bump line)"
  run --separate-stderr cr run -- "$c"
  k=$(jq -r .key <<< "$output")
  run --separate-stderr cr run -- "$c"
  [ "$(log_lines)" -eq 2 ]
  jq -e -s --arg c "$c" --arg k "$k" '
    length == 2
    and all(.[]; (keys | sort) == ["at", "command", "key", "result", "secs", "would_reuse"])
    and all(.[]; .command == $c and .key == $k and .result == "PASS" and (.secs | type) == "number")
    and (map(.would_reuse) == [false, true])' "$L/shadow.log"
}

@test "stats: runs, would_reuse, agreed, seconds reusable and every disagreement" {
  ok="sleep 1"
  flaky="test ! -f '$OUTSIDE/broken'"
  red="false"
  run --separate-stderr cr run -- "$ok"
  run --separate-stderr cr run -- "$ok"
  run --separate-stderr cr run -- "$flaky"
  touch "$OUTSIDE/broken"
  run --separate-stderr cr run -- "$flaky"
  [ "$status" -eq 1 ]
  run --separate-stderr cr run -- "$red"
  run --separate-stderr cr run -- "$red"
  run --separate-stderr cr stats
  [ "$status" -eq 0 ]
  jq -e '.runs == 6 and .would_reuse == 2 and .agreed == 1' <<< "$output"
  jq -e '.secs_reusable >= 1' <<< "$output"
  # A fresh FAIL with nothing to reuse is not a disagreement; only the flaky
  # check that would have reused a PASS and failed is.
  jq -e --arg c "$flaky" '.disagreed | length == 1 and .[0].command == $c and (.[0].at | length) > 0' <<< "$output"
}

@test "stats on a repository with no shadow line yet: zero runs, then one" {
  run --separate-stderr cr stats
  [ "$status" -eq 0 ]
  jq -e '.runs == 0 and .disagreed == []' <<< "$output"
  run --separate-stderr cr run -- "true"
  run --separate-stderr cr stats
  jq -e '.runs == 1 and .would_reuse == 0' <<< "$output"
}

@test "shadow.log is capped at 5000 lines, the oldest dropped first" {
  mkdir -p "$L"
  {
    jq -nc '{at: "2020-01-01T00:00:00Z", command: "oldest-line", key: "k", would_reuse: false, result: "PASS", secs: 0}'
    jq -nc '{at: "2025-06-01T00:00:00Z", command: "filler", key: "k", would_reuse: false, result: "PASS", secs: 0}' |
      awk '{ for (i = 0; i < 4999; i++) print }'
  } > "$L/shadow.log"
  [ "$(log_lines)" -eq 5000 ]
  c="$(bump cap)"
  run --separate-stderr cr run -- "$c"
  [ "$status" -eq 0 ]
  [ "$(log_lines)" -eq 5000 ]
  [ "$(grep -c oldest-line "$L/shadow.log" || true)" -eq 0 ]
  [ "$(tail -1 "$L/shadow.log" | jq -r .command)" = "$c" ]
}

@test "a shadow line that cannot be written: verdict and exit code kept, a warning" {
  if [ "$(id -u)" -eq 0 ]; then skip "root writes a read-only directory"; fi
  mkdir -p "$L"
  : > "$L/shadow.log"
  chmod 444 "$L/shadow.log"
  chmod 555 "$L"
  run --separate-stderr cr run -- "$(bump rs); exit 0"
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .mode == "shadow"' <<< "$output"
  [ -n "$stderr" ]
  run --separate-stderr cr run -- "$(bump rs); exit 1"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL"' <<< "$output"
  [ -n "$stderr" ]
  [ "$(counter rs)" -eq 2 ]
  chmod 755 "$L"
  [ "$(log_lines)" -eq 0 ]
}
