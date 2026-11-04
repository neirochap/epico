#!/usr/bin/env bats
# scripts/check-reuse.sh run — the ledger under concurrency, signals and a
# command that cannot start (R2.15, R2.16, R4.8).
#
#   - Two checks that record at once keep both entries, and an older result is
#     never put back over a newer one for the same key: a PASS recorded before a
#     FAIL must not survive the FAIL, or mode `on` would reuse it.
#   - The ledger lock is a directory beside the ledger; a lock older than a
#     minute belonged to a killed run and is broken, a lock that stays held costs
#     the record only, never the verdict or the exit code.
#   - A command that cannot be started (no temporary file, no setsid) is FAIL with
#     exit 126 and records nothing: it must never replace a real PASS.
#   - A TERM to the runner stops the command it started and leaves no temp file.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
  MARKER=""
}

teardown() {
  # A case that failed half way must not leave a sleeping command behind.
  if [ -n "${MARKER:-}" ]; then pkill -KILL -f -- "$MARKER" 2>/dev/null || true; fi
  if [ -n "${RPID:-}" ]; then kill -KILL "$RPID" 2>/dev/null || true; fi
  reuse_teardown
}

# run_together <command>... — one `run` per argument, all started at once; waits
# for every one. A FAIL exits 1, which is not an error here.
run_together() {
  local pids=() c p
  for c in "$@"; do
    bash "$CR" run -- "$c" >/dev/null 2>&1 3>&- &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
}

entries_count() { jq '.entries | length' "$LD/ledger.json"; }

# wait_gone <pid> — up to 10 s for the process to exit; a zombie counts as gone
# (a container whose PID 1 never reaps keeps a killed process in the table).
wait_gone() {
  local i state
  for i in $(seq 1 100); do
    state=$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null || true)
    if [ -z "$state" ] || [ "$state" = Z ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# --- R4.8: two checks recording at once ---

@test "a FAIL recorded while six other results are written is not overwritten by the older PASS" {
  local flag="$OUTSIDE/flag" kcmd round k
  kcmd="test -f '$flag'"
  k=$(key_of "$kcmd")
  is_hash "$k"
  for round in 1 2 3; do
    # K holds a PASS; the flag goes away, so K's next run is a FAIL that must win.
    touch "$flag"
    run --separate-stderr bash "$CR" run -- "$kcmd"
    [ "$status" -eq 0 ]
    jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
    rm -f "$flag"
    run_together "$kcmd" "true # w1-$round" "true # w2-$round" "true # w3-$round" \
      "true # w4-$round" "true # w5-$round" "true # w6-$round"
    if ! jq -e --arg k "$k" '.entries[$k].result == "FAIL"' "$LD/ledger.json"; then
      echo "round $round: the older PASS for the key survived the newer FAIL"
      return 1
    fi
    # Every writer's entry is there: K plus the six PASS writers of this round.
    [ "$(jq -r '[.entries[] | select(.command | test("^true # w[1-6]-'"$round"'$"))] | length' "$LD/ledger.json")" -eq 6 ]
    [ ! -d "$LD/ledger.lock" ]
  done
}

@test "twelve parallel runs on distinct keys keep twelve entries and leave no lock behind" {
  local i cmds=()
  for i in $(seq 1 12); do cmds+=("true # distinct-$i"); done
  run_together "${cmds[@]}"
  [ "$(entries_count)" -eq 12 ]
  for i in $(seq 1 12); do
    jq -e --arg c "true # distinct-$i" '[.entries[] | select(.command == $c and .result == "PASS")] | length == 1' "$LD/ledger.json"
  done
  if [ -e "$LD/ledger.lock" ]; then echo "the ledger lock was left behind"; return 1; fi
  # Nothing but the ledger and the shadow log: no temp file of a writer.
  [ "$(find "$LD" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 2 ]
  jq -e . "$LD/ledger.json" > /dev/null
}

@test "a lock older than a minute is broken and the result is recorded" {
  local k
  mkdir -p "$LD/ledger.lock"
  touch -t 200001010000 "$LD/ledger.lock"
  k=$(key_of "true # after-stale")
  SECONDS=0
  run --separate-stderr bash "$CR" run -- "true # after-stale"
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 30 ]
  jq -e '.result == "PASS" and .exit == 0' <<< "$output"
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  if [ -e "$LD/ledger.lock" ]; then echo "the stale lock, or the new one, is still there"; return 1; fi
  [ "$(find "$LD" -maxdepth 1 -name 'ledger.lock*' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "a lock that stays held keeps the verdict and the exit code, warns, and records nothing" {
  local k
  mkdir -p "$LD/ledger.lock"
  k=$(key_of "true # held-pass")
  run --separate-stderr bash "$CR" run -- "true # held-pass"
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .exit == 0 and .decision == "ran"' <<< "$output"
  [[ "$stderr" == *"not recorded"* ]]
  run --separate-stderr bash "$CR" run -- "echo broken; exit 3"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3 and .evidence == "broken"' <<< "$output"
  [[ "$stderr" == *"not recorded"* ]]
  # The lock is not ours: it is still held, and nothing was written under it.
  [ -d "$LD/ledger.lock" ]
  if [ -e "$LD/ledger.json" ]; then
    jq -e --arg k "$k" '.entries[$k] == null' "$LD/ledger.json"
  fi
}

# --- R2.15: a command that cannot be started ---

@test "an unusable TMPDIR is FAIL with exit 126, runs nothing and leaves a recorded PASS in place" {
  local k before
  run --separate-stderr bash "$CR" run -- "$(bump started)"
  [ "$status" -eq 0 ]
  [ "$(counter started)" -eq 1 ]
  k=$(jq -r .key <<< "$output")
  is_hash "$k"
  before=$(cksum < "$LD/ledger.json")
  lines_before=$(wc -l < "$LD/shadow.log" | tr -d ' ')

  TMPDIR="$WORK/does/not/exist" run --separate-stderr bash "$CR" run --fresh -- "$(bump started)"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 126 and .decision == "ran"' <<< "$output"
  jq -e '.evidence | test("temporary file")' <<< "$output"
  [ "$(jq -r .key <<< "$output")" = "$k" ]
  # The command never ran, the PASS is untouched, and nothing was appended.
  [ "$(counter started)" -eq 1 ]
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  [ "$(cksum < "$LD/ledger.json")" = "$before" ]
  [ "$(wc -l < "$LD/shadow.log" | tr -d ' ')" -eq "$lines_before" ]
}

@test "a machine with no setsid is FAIL with exit 126, runs nothing and records nothing" {
  local k tool bin="$WORK/nosetsid" before lines_before
  mkdir -p "$bin"
  for tool in bash env sh git jq timeout mktemp cp rm mv mkdir rmdir cat sed tr cut awk grep \
    tail head wc date find sleep sort dirname tee ls uname id kill; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  [ ! -e "$bin/setsid" ]
  run --separate-stderr bash "$CR" run -- "$(bump started)"
  [ "$status" -eq 0 ]
  k=$(jq -r .key <<< "$output")
  is_hash "$k"
  before=$(cksum < "$LD/ledger.json")
  lines_before=$(wc -l < "$LD/shadow.log" | tr -d ' ')

  PATH="$bin" run --separate-stderr "$bin/bash" "$CR" run --fresh -- "$(bump started)"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 126' <<< "$output"
  jq -e '.evidence | test("setsid")' <<< "$output"
  [ "$(counter started)" -eq 1 ]
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  [ "$(cksum < "$LD/ledger.json")" = "$before" ]
  [ "$(wc -l < "$LD/shadow.log" | tr -d ' ')" -eq "$lines_before" ]
}

@test "a command that cannot start records nothing even where no PASS was recorded" {
  run --separate-stderr env TMPDIR="$WORK/does/not/exist" bash "$CR" run -- "$(bump never)"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 126' <<< "$output"
  [ "$(counter never)" -eq 0 ]
  if [ -e "$LD/ledger.json" ]; then
    jq -e '.entries | length == 0' "$LD/ledger.json"
  fi
  if [ -e "$LD/shadow.log" ]; then
    [ ! -s "$LD/shadow.log" ]
  fi
}

# --- R2.16: a TERM to the runner ---

@test "a TERM to the runner stops the command it started and leaves no temp file" {
  local i marker cmd pidf="$OUTSIDE/cmd.pid" priv="$WORK/tmp"
  marker="epico-term-$$-$RANDOM-$RANDOM"
  MARKER="$marker"
  mkdir -p "$priv"
  cmd="echo \$\$ > '$pidf'; exec sleep 300 # $marker"

  TMPDIR="$priv" bash "$CR" run --timeout 120 -- "$cmd" > "$OUTSIDE/term.out" 2> "$OUTSIDE/term.err" 3>&- &
  RPID=$!
  for i in $(seq 1 100); do
    if [ -s "$pidf" ]; then break; fi
    sleep 0.1
  done
  [ -s "$pidf" ]
  local cpid
  cpid=$(cat "$pidf")
  kill -0 "$cpid"
  # While it runs the runner holds temp files: the assertion below is not vacuous.
  [ "$(find "$priv" -type f | wc -l | tr -d ' ')" -gt 0 ]

  kill -TERM "$RPID"
  wait_gone "$RPID" || { echo "the runner did not exit"; return 1; }
  wait_gone "$cpid" || { echo "the checked command (pid $cpid) is still running after the runner was terminated"; return 1; }
  for i in $(seq 1 50); do
    if ! pgrep -f -- "$marker" > /dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -f -- "$marker" > /dev/null; then echo "a process of the checked command is still alive"; return 1; fi
  [ "$(find "$priv" -type f | wc -l | tr -d ' ')" -eq 0 ]
  [ "$(find "$PROJ/.git" -maxdepth 1 -name 'epico-fp.*' | wc -l | tr -d ' ')" -eq 0 ]
  [ ! -d "$LD/ledger.lock" ]
  RPID=""
}
