#!/usr/bin/env bats
# scripts/check-reuse.sh run — the ledger lock wait always ends, and a release
# removes only the run's own lock (R4.10, R4.11).
#
#   - A stale lock (older than a minute) that cannot be moved aside — the ledger
#     directory is not writable — ends the wait: the run warns "not recorded",
#     keeps the check's verdict and exit code, and ends promptly.
#   - The holder names itself in ledger.lock/owner. A run whose lock was broken
#     as stale and taken by another holder leaves that holder's lock and owner
#     token in place when it releases — on a normal finish (ledger_unlock) and on
#     a TERM (cleanup). A run whose lock nobody took still removes it.
#
# Holding the lock on purpose: the lock is held only around the ledger rewrite,
# a few milliseconds. A `jq` on PATH in front of the real one pauses the FIRST
# call the run makes while ledger.lock/owner exists — the ledger read under the
# lock — until the test says go, then runs the real jq. The run really holds
# the real lock while it waits; nothing in the script is replaced.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
  GATE="$WORK/gate"
  RPID=""
}

teardown() {
  # A case that failed half way must not leave a paused runner behind.
  if [ -n "${GATE:-}" ] && [ -d "$GATE" ]; then touch "$GATE/go" 2>/dev/null || true; fi
  if [ -n "${RPID:-}" ]; then kill -KILL "$RPID" 2>/dev/null || true; fi
  reuse_teardown
}

# gate_arm — a jq in $GATE that, while ledger.lock/owner exists, pauses the
# first call (one-shot) until $GATE/go appears, at most ~30 s, then runs the
# real jq. Pass PATH="$GATE:$PATH" to the run alone.
gate_arm() {
  local real
  real=$(command -v jq)
  mkdir -p "$GATE"
  rm -f -- "$GATE/paused" "$GATE/go" "$GATE/taken"
  cat > "$GATE/jq" <<EOF
#!/usr/bin/env bash
if [ -e '$GATE/armed' ] && [ -s '$LD/ledger.lock/owner' ] && mv -- '$GATE/armed' '$GATE/taken' 2>/dev/null; then
  touch '$GATE/paused'
  i=0
  while [ ! -e '$GATE/go' ] && [ "\$i" -lt 1500 ]; do sleep 0.02; i=\$((i + 1)); done
fi
exec '$real' "\$@"
EOF
  chmod +x "$GATE/jq"
  touch "$GATE/armed"
}

# gate_wait_paused — until the run is paused holding the lock, at most ~10 s.
gate_wait_paused() {
  local _
  for _ in $(seq 1 500); do
    if [ -e "$GATE/paused" ]; then return 0; fi
    sleep 0.02
  done
  echo "the run never paused while holding the lock"
  return 1
}

# start_held <command> — a run of <command> in the background, paused while it
# holds the ledger lock; RPID is the runner. Its stdout goes to $OUTSIDE/run.out.
start_held() {
  # No lock before the run: the one the gate sees is the run's own.
  [ ! -e "$LD/ledger.lock" ]
  gate_arm
  PATH="$GATE:$PATH" bash "$CR" run --fresh -- "$1" > "$OUTSIDE/run.out" 2> "$OUTSIDE/run.err" 3>&- &
  RPID=$!
  gate_wait_paused
  [ -d "$LD/ledger.lock" ]
  # The lock is the runner's: its token is "<pid> <random>".
  [[ "$(cat -- "$LD/ledger.lock/owner")" == "$RPID "* ]]
}

# take_over <token> — what a waiter does to a lock it judged stale: set it
# aside, remove it, take a fresh lock and name itself <token>.
take_over() {
  mv -- "$LD/ledger.lock" "$LD/ledger.lock.stale.test"
  rm -rf -- "$LD/ledger.lock.stale.test"
  mkdir -- "$LD/ledger.lock"
  printf '%s\n' "$1" > "$LD/ledger.lock/owner"
}

# finish — let the paused run go and wait for it; RSTATUS is its exit status.
finish() {
  touch "$GATE/go"
  RSTATUS=0
  wait "$RPID" || RSTATUS=$?
  RPID=""
}

@test "a stale lock in a ledger directory the runner cannot write ends the wait within 15 s, warns, and keeps the verdict and exit code" {
  if [ "$(id -u)" -eq 0 ]; then skip "root writes a read-only directory"; fi
  local cmd="echo broken; exit 3"
  # Something recorded first, so the ledger directory exists.
  run --separate-stderr bash "$CR" run -- "$cmd"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3' <<< "$output"
  [ -f "$LD/ledger.json" ]

  # The lock of a run killed long ago, in a directory nobody can write.
  mkdir -- "$LD/ledger.lock"
  printf 'dead-holder 1\n' > "$LD/ledger.lock/owner"
  touch -t 200001010000 "$LD/ledger.lock"
  chmod a-w "$LD"

  # An outer timeout, so an endless wait is a failed assertion, not a hung suite.
  SECONDS=0
  run --separate-stderr timeout -k 2 20 bash "$CR" run --fresh -- "$cmd"
  local elapsed=$SECONDS
  chmod u+w "$LD"
  if [ "$elapsed" -ge 15 ]; then
    echo "the wait on an unmovable stale lock did not end: ${elapsed}s, status $status"
    return 1
  fi
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3 and .decision == "ran"' <<< "$output"
  [[ "$stderr" == *"not recorded"* ]]
  # The stale lock was not ours to remove, and could not be moved: still there.
  [ -d "$LD/ledger.lock" ]
}

@test "a run whose lock was taken over by a holder with the same pid leaves that holder's lock and owner in place when it finishes" {
  local cmd="true # takeover-finish" mine theirs r
  run --separate-stderr bash "$CR" run -- "$cmd"
  [ "$status" -eq 0 ]
  [ -f "$LD/ledger.json" ]

  start_held "$cmd"
  mine=$(cat -- "$LD/ledger.lock/owner")
  # Hostile: the new holder's token shares the runner's pid and differs only in
  # its random part — a release that matched on the pid alone would take it.
  r=${mine#* }
  theirs="$RPID $(( (r + 1) % 32768 ))"
  [ "$theirs" != "$mine" ]
  take_over "$theirs"

  finish
  [ "$RSTATUS" -eq 0 ]
  jq -e '.result == "PASS" and .exit == 0' "$OUTSIDE/run.out"
  if [ ! -d "$LD/ledger.lock" ]; then
    echo "the run released a lock that was no longer its own"
    return 1
  fi
  [ -f "$LD/ledger.lock/owner" ]
  [ "$(cat -- "$LD/ledger.lock/owner")" = "$theirs" ]
}

@test "a run whose lock was taken over, stopped by TERM while it held it, leaves the new holder's lock and owner in place" {
  local cmd="true # takeover-term" theirs
  run --separate-stderr bash "$CR" run -- "$cmd"
  [ "$status" -eq 0 ]

  start_held "$cmd"
  theirs="new-holder $RANDOM"
  take_over "$theirs"

  # The TERM lands while the run is paused under the lock; cleanup releases.
  kill -TERM "$RPID"
  finish
  [ "$RSTATUS" -ne 0 ]
  if [ ! -d "$LD/ledger.lock" ]; then
    echo "cleanup released a lock that was no longer its own"
    return 1
  fi
  [ -f "$LD/ledger.lock/owner" ]
  [ "$(cat -- "$LD/ledger.lock/owner")" = "$theirs" ]
}

@test "a run whose lock nobody took still removes it, on a normal finish and on TERM" {
  local cmd="true # own-lock"
  run --separate-stderr bash "$CR" run -- "$cmd"
  [ "$status" -eq 0 ]

  start_held "$cmd"
  finish
  [ "$RSTATUS" -eq 0 ]
  jq -e '.result == "PASS"' "$OUTSIDE/run.out"
  [ "$(find "$LD" -maxdepth 2 \( -name 'ledger.lock*' -o -name owner \) | wc -l | tr -d ' ')" -eq 0 ]

  start_held "$cmd"
  kill -TERM "$RPID"
  finish
  [ "$RSTATUS" -ne 0 ]
  [ "$(find "$LD" -maxdepth 2 \( -name 'ledger.lock*' -o -name owner \) | wc -l | tr -d ' ')" -eq 0 ]
}
