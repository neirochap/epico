#!/usr/bin/env bats
# scripts/check-reuse.sh — void markers on every path a non-PASS is dropped,
# named in the reason, and bounded by the ledger (R4.9, R4.12).
#
#   - A non-PASS that is not recorded voids its key (`void.<key>` beside the
#     ledger), whether the lock was given up on or a write UNDER the lock failed:
#     the older PASS for that key is never reused in mode `on`.
#   - When a void forced the miss, `run` and `lookup` say so in `reason`.
#   - Each recorded write removes the `void.*` markers whose key has no entry in
#     the ledger it wrote; a void whose key the ledger holds stays.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
}

teardown() {
  reuse_teardown
}

# pad_ledger <n> — adds <n> entries of ~250 bytes each to the ledger, written
# through a temp file and a rename. They keep every entry already there.
pad_ledger() {
  local tmp="$LD/pad.tmp"
  jq -c --argjson n "$1" '
    .entries += ([range(0; $n) | {
      key: ("pad-\(.)"),
      value: {command: ("pad \(.) " + ("x" * 200)), result: "PASS",
              fingerprint: "pad", at: "2000-01-01T00:00:00Z", secs: 0}
    }] | from_entries)' "$LD/ledger.json" > "$tmp"
  mv -f -- "$tmp" "$LD/ledger.json"
}

# small_files <command…> — runs check-reuse with a file-size limit of 8 KiB.
# The ledger read goes through pipes (here-strings under 64 KiB) and stays whole;
# the rewrite of a ledger larger than 8 KiB cannot be written, so the jq step
# under the lock fails while the lock itself is taken and released normally.
# SIGXFSZ is ignored, so the oversized write fails with EFBIG instead of a kill.
small_files() {
  bash -c 'trap "" XFSZ; ulimit -c 0; ulimit -f 8; exec bash "$@"' _ "$CR" "$@"
}

@test "a FAIL whose ledger rewrite fails under the lock leaves the key's earlier PASS unreused in mode on" {
  local flag="$OUTSIDE/flag" kcmd k
  profile_mode on
  kcmd="test -f '$flag'"
  k=$(key_of "$kcmd")
  is_hash "$k"
  touch "$flag"
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran" and .result == "PASS"' <<< "$output"
  pad_ledger 80
  [ "$(wc -c < "$LD/ledger.json" | tr -d ' ')" -gt 16384 ]
  [ "$(wc -c < "$LD/ledger.json" | tr -d ' ')" -lt 49152 ]
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  rm -f "$flag"

  # The FAIL runs, takes the lock, and its rewrite of the ledger fails.
  run --separate-stderr small_files run --fresh -- "$kcmd"
  [ "$status" -eq 1 ]
  jq -e '.decision == "ran" and .result == "FAIL"' <<< "$output"
  [[ "$stderr" == *"not recorded"* ]]
  [ ! -e "$LD/ledger.lock" ]
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"

  # The dropped FAIL voids the older PASS: the next run checks again.
  run --separate-stderr bash "$CR" lookup -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.would_reuse == false' <<< "$output"
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 1 ]
  jq -e '.decision == "ran" and .result == "FAIL"' <<< "$output"
}

@test "lookup and run on a voided key report no reuse and a reason naming the void; an unvoided key's reason does not" {
  local kcmd other k ko
  profile_mode on
  kcmd="true # voided"
  other="true # not voided"
  k=$(key_of "$kcmd")
  ko=$(key_of "$other")
  is_hash "$k"
  is_hash "$ko"
  [ "$k" != "$ko" ]
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  run --separate-stderr bash "$CR" run -- "$other"
  [ "$status" -eq 0 ]
  jq -e --arg k "$k" --arg o "$ko" '.entries[$k].result == "PASS" and .entries[$o].result == "PASS"' "$LD/ledger.json"
  : > "$LD/void.$k"

  # The hostile half first: the key that is NOT void is reused, and its reason
  # does not speak of a void.
  run --separate-stderr bash "$CR" lookup -- "$other"
  [ "$status" -eq 0 ]
  jq -e '.would_reuse == true and ((.reason // "") | test("void"; "i") | not)' <<< "$output"

  run --separate-stderr bash "$CR" lookup -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e --arg k "$k" '.key == $k and .would_reuse == false and .last.result == "PASS"' <<< "$output"
  jq -e '(.reason // "") | test("void"; "i")' <<< "$output"

  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran" and .result == "PASS"' <<< "$output"
  jq -e '(.reason // "") | test("void"; "i")' <<< "$output"
}

@test "a void whose key the ledger does not hold is removed by the next recorded run of another key; a void whose key it holds stays" {
  local kcmd other gone k ko kg
  profile_mode on
  kcmd="true # held"
  other="true # another key"
  gone="true # never recorded"
  k=$(key_of "$kcmd")
  ko=$(key_of "$other")
  kg=$(key_of "$gone")
  is_hash "$k"
  is_hash "$ko"
  is_hash "$kg"
  [ "$k" != "$ko" ]
  [ "$k" != "$kg" ]
  [ "$ko" != "$kg" ]
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e --arg g "$kg" '.entries | has($g) | not' "$LD/ledger.json"
  : > "$LD/void.$kg"
  : > "$LD/void.$k"

  run --separate-stderr bash "$CR" run -- "$other"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran" and .result == "PASS"' <<< "$output"
  jq -e --arg o "$ko" '.entries[$o].result == "PASS"' "$LD/ledger.json"

  # Bounded: the marker for a key the ledger does not hold is gone.
  [ ! -e "$LD/void.$kg" ]
  [ "$(find "$LD" -maxdepth 1 -name 'void.*' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "a void whose key is in the ledger survives another key's recorded run and still forces a miss" {
  local kcmd other k ko
  profile_mode on
  kcmd="true # held"
  other="true # another key"
  k=$(key_of "$kcmd")
  ko=$(key_of "$other")
  is_hash "$k"
  is_hash "$ko"
  [ "$k" != "$ko" ]
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  : > "$LD/void.$k"

  run --separate-stderr bash "$CR" run -- "$other"
  [ "$status" -eq 0 ]
  jq -e --arg o "$ko" '.entries[$o].result == "PASS"' "$LD/ledger.json"

  [ -e "$LD/void.$k" ]
  run --separate-stderr bash "$CR" lookup -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.would_reuse == false' <<< "$output"
}
