#!/usr/bin/env bats
# scripts/check-reuse.sh run — the ledger lock under a queue of writers, and a
# result the lock kept out (R4.8).
#
#   - The holder of `ledger.lock` names itself in `ledger.lock/owner`. A waiter's
#     ~5 s budget counts ONE holder: it restarts whenever the owner changes, so a
#     lock that keeps changing hands never makes a newer FAIL give up.
#   - A lock held by one owner (or by none, a bare directory) past the budget
#     still gives up: nothing is recorded and the runner warns "not recorded".
#   - When that give-up drops a non-PASS result, the key is voided
#     (`void.<key>` beside the ledger): the older PASS is never reused in mode
#     `on`, and the next recorded run of that key clears the void.
#   - Release removes the owner token, then the directory: no lock is left.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
  HOLDER=""
}

teardown() {
  # A case that failed half way must not leave the lock holder cycling.
  if [ -n "${HOLDER:-}" ]; then kill -KILL "$HOLDER" 2>/dev/null || true; fi
  reuse_teardown
}

# hand_over <holds> — the ledger lock passed down a queue of <holds> writers,
# about 0.3 s each, each naming itself with a NEW owner token. The directory is
# never absent between two holders (the next one takes over the moment the last
# lets go), so a waiter can never slip in between them: it must outlast the
# whole queue, which is what a budget per owner is for. The last holder removes
# its token, then the directory. Run in the background.
hand_over() {
  local lock="$LD/ledger.lock" i
  until mkdir -- "$lock" 2>/dev/null; do sleep 0.02; done
  for i in $(seq 1 "$1"); do
    rm -f -- "$lock/owner"
    printf 'holder-%s-%s\n' "$$" "$i" > "$lock/owner"
    sleep 0.3
  done
  rm -f -- "$lock/owner"
  rmdir -- "$lock"
}

@test "a lock that changes hands for longer than the wait does not make a FAIL's record give up, and the ledger holds the FAIL" {
  local flag="$OUTSIDE/flag" kcmd k i
  kcmd="test -f '$flag'"
  k=$(key_of "$kcmd")
  is_hash "$k"
  touch "$flag"
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  rm -f "$flag"

  # About 8 s of holders, one after another: longer than one 5 s wait, while no
  # single holder keeps the lock for more than 0.3 s.
  hand_over 26 3>&- &
  HOLDER=$!
  for i in $(seq 1 50); do
    if [ -s "$LD/ledger.lock/owner" ]; then break; fi
    sleep 0.02
  done
  [ -d "$LD/ledger.lock" ]

  SECONDS=0
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .decision == "ran"' <<< "$output"
  wait "$HOLDER" || true
  HOLDER=""
  [ "$SECONDS" -lt 30 ]
  if [[ "$stderr" == *"not recorded"* ]]; then
    echo "the FAIL gave up on a lock that kept changing hands: $stderr"
    return 1
  fi
  jq -e --arg k "$k" '.entries[$k].result == "FAIL"' "$LD/ledger.json"
  [ ! -e "$LD/ledger.lock" ]
}

@test "a lock held by one owner past the wait leaves the FAIL unrecorded, yet the key's PASS is not reused; the next recorded run clears the void" {
  local flag="$OUTSIDE/flag" kcmd k other ko
  profile_mode on
  kcmd="test -f '$flag'"
  other="true # another key"
  k=$(key_of "$kcmd")
  ko=$(key_of "$other")
  is_hash "$k"
  is_hash "$ko"
  [ "$k" != "$ko" ]
  touch "$flag"
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran" and .result == "PASS"' <<< "$output"
  run --separate-stderr bash "$CR" run -- "$other"
  [ "$status" -eq 0 ]
  jq -e --arg k "$k" --arg o "$ko" '.entries[$k].result == "PASS" and .entries[$o].result == "PASS"' "$LD/ledger.json"
  rm -f "$flag"

  # One holder that never lets go, never names a new owner: the wait gives up.
  mkdir -p "$LD/ledger.lock"
  run --separate-stderr bash "$CR" run --fresh -- "$kcmd"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .decision == "ran"' <<< "$output"
  [[ "$stderr" == *"not recorded"* ]]
  # Nothing written under a lock that is not ours: the ledger still says PASS.
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  rm -f -- "$LD/ledger.lock/owner"
  rmdir -- "$LD/ledger.lock"

  # The dropped FAIL voids the older PASS: it is no hit, so the check runs.
  run --separate-stderr bash "$CR" lookup -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.would_reuse == false' <<< "$output"
  [ -e "$LD/void.$k" ]
  # The void is the key's alone: another key's PASS is still reused.
  run --separate-stderr bash "$CR" run -- "$other"
  [ "$status" -eq 0 ]
  jq -e '.decision == "reused" and .result == "PASS"' <<< "$output"
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 1 ]
  jq -e '.decision == "ran" and .result == "FAIL"' <<< "$output"
  jq -e --arg k "$k" '.entries[$k].result == "FAIL"' "$LD/ledger.json"

  # That recorded run cleared the void: a PASS recorded after it is reused.
  [ ! -e "$LD/void.$k" ]
  touch "$flag"
  run --separate-stderr bash "$CR" run --fresh -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.decision == "ran" and .result == "PASS"' <<< "$output"
  run --separate-stderr bash "$CR" run -- "$kcmd"
  [ "$status" -eq 0 ]
  jq -e '.decision == "reused" and .result == "PASS"' <<< "$output"
}

@test "release leaves no ledger.lock and no owner token behind after ordinary runs" {
  local i pids=() p
  run --separate-stderr bash "$CR" run -- "true # alone"
  [ "$status" -eq 0 ]
  run --separate-stderr bash "$CR" run -- "echo broken; exit 3"
  [ "$status" -eq 1 ]
  [ ! -e "$LD/ledger.lock" ]
  for i in $(seq 1 6); do
    bash "$CR" run -- "true # queued-$i" > /dev/null 2>&1 3>&- &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
  [ "$(jq '.entries | length' "$LD/ledger.json")" -eq 8 ]
  [ ! -e "$LD/ledger.lock" ]
  [ "$(find "$LD" -maxdepth 2 \( -name 'ledger.lock*' -o -name owner \) | wc -l | tr -d ' ')" -eq 0 ]
}
