#!/usr/bin/env bats
# scripts/check-reuse.sh run — a stale ledger lock is broken by one run at a
# time, and its waiters keep waiting (R4.8, R4.10, R4.13, R4.14).
#
#   - A lock older than a minute belonged to a run that was killed. Several runs
#     waiting on it all record their results: when one breaks it and takes a
#     fresh lock, the others wait on the new holder instead of giving up.
#   - A breaker moves a lock aside only while it is still stale and its owner is
#     still the one it judged dead. Breaking is two steps, "is it stale?" then
#     "move it": a lock another run broke and took in between is a live lock,
#     and stays in place with its owner.
#   - A break file older than a minute, left by a breaker that was killed, does
#     not stop the break.
#   - A stale lock in a ledger directory that cannot be written still ends the
#     wait.
#
# Making the windows certain: a `find` on PATH in front of the real one, for the
# runs only (PATH="$FS/bin:$PATH"). It acts on each run's FIRST find of
# ledger.lock (the staleness check), once per run (FIND_ID), and only delays:
# every call still runs the real find and returns its answer.
#   FIND_MODE=follow  the first run to get there is the leader and goes on at
#                     once; the others wait (at most ~8 s) until the lock no
#                     longer holds the dead owner — the leader has broken it —
#                     and only then look.
#   FIND_MODE=pause   look, then pause (at most ~30 s) until $FS/state/go, then
#                     answer: a breaker held between "is it stale" and "move".
#   FIND_MODE=after   wait (at most ~10 s) until the paused run is paused.
# A `jq` gate (as in check-reuse-lock-release.bats) holds a run under the real
# lock it took: it pauses the first jq call made while ledger.lock/owner holds
# a live owner, until $GATE/go.

bats_require_minimum_version 1.5.0

DEAD="dead-holder 1"

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
  FS="$WORK/findshim"
  GATE="$WORK/gate"
  PIDS=()
  find_shim_install
}

teardown() {
  # A case that failed half way must not leave a paused run behind.
  touch "$FS/state/go" 2>/dev/null || true
  if [ -d "$GATE" ]; then touch "$GATE/go" 2>/dev/null || true; fi
  local p
  for p in "${PIDS[@]}"; do kill -KILL "$p" 2>/dev/null || true; done
  reuse_teardown
}

# find_shim_install — the delaying find at $FS/bin/find; its state in $FS/state.
find_shim_install() {
  mkdir -p "$FS/bin" "$FS/state"
  command -v find > "$FS/state/real"
  cat > "$FS/bin/find" <<'EOF'
#!/usr/bin/env bash
bin=${0%/*}
S=${bin%/*}/state
real=$(cat -- "$S/real")
lock=""
for a in "$@"; do
  case "$a" in */ledger.lock) lock=$a ;; esac
done
if [ -z "$lock" ] || [ -z "${FIND_ID:-}" ] || ! (set -o noclobber; true > "$S/once.$FIND_ID") 2>/dev/null; then
  exec "$real" "$@"
fi
printf '%s\n' "$FIND_ID" >> "$S/calls"
i=0
case "${FIND_MODE:-}" in
  follow)
    if (set -o noclobber; true > "$S/leader") 2>/dev/null; then exec "$real" "$@"; fi
    while [ "$(cat -- "$lock/owner" 2>/dev/null || true)" = "$FIND_DEAD" ] && [ "$i" -lt 400 ]; do
      sleep 0.02
      i=$((i + 1))
    done
    exec "$real" "$@"
    ;;
  pause)
    out=$("$real" "$@")
    rc=$?
    true > "$S/paused"
    while [ ! -e "$S/go" ] && [ "$i" -lt 1500 ]; do sleep 0.02; i=$((i + 1)); done
    if [ -n "$out" ]; then printf '%s\n' "$out"; fi
    exit "$rc"
    ;;
  after)
    while [ ! -e "$S/paused" ] && [ "$i" -lt 500 ]; do sleep 0.02; i=$((i + 1)); done
    exec "$real" "$@"
    ;;
esac
exec "$real" "$@"
EOF
  chmod +x "$FS/bin/find"
}

find_shim_reset() {
  rm -f -- "$FS/state/once."* "$FS/state/leader" "$FS/state/paused" "$FS/state/go" "$FS/state/calls"
}

# gate_arm — a jq in $GATE that pauses the first call (one-shot) made while
# ledger.lock/owner holds an owner other than the dead one, until $GATE/go
# appears, at most ~30 s, then runs the real jq.
gate_arm() {
  local real
  real=$(command -v jq)
  mkdir -p "$GATE"
  rm -f -- "$GATE/paused" "$GATE/go" "$GATE/taken"
  cat > "$GATE/jq" <<EOF
#!/usr/bin/env bash
o=\$(cat -- '$LD/ledger.lock/owner' 2>/dev/null || true)
if [ -e '$GATE/armed' ] && [ -n "\$o" ] && [ "\$o" != '$DEAD' ] && mv -- '$GATE/armed' '$GATE/taken' 2>/dev/null; then
  touch '$GATE/paused'
  i=0
  while [ ! -e '$GATE/go' ] && [ "\$i" -lt 1500 ]; do sleep 0.02; i=\$((i + 1)); done
fi
exec '$real' "\$@"
EOF
  chmod +x "$GATE/jq"
  touch "$GATE/armed"
}

# plant_stale — the lock of a run killed long ago: its directory and its owner.
plant_stale() {
  mkdir -p -- "$LD"
  mkdir -- "$LD/ledger.lock"
  printf '%s\n' "$DEAD" > "$LD/ledger.lock/owner"
  touch -t 200001010000 "$LD/ledger.lock/owner" "$LD/ledger.lock"
}

# wait_file <path> <tries> — until <path> exists, 0.02 s apart.
wait_file() {
  local _
  for _ in $(seq 1 "$2"); do
    if [ -e "$1" ]; then return 0; fi
    sleep 0.02
  done
  return 1
}

# no_lock_left — no ledger.lock, owner or break file anywhere in the ledger dir.
no_lock_left() {
  local left
  left=$(find "$LD" -maxdepth 2 \( -name 'ledger.lock*' -o -name owner \) | tr '\n' ' ')
  if [ -n "$left" ]; then
    echo "a lock, owner or break file was left behind: $left"
    return 1
  fi
}

# not_recorded_in <file>... — how many of the files warn "not recorded".
not_recorded_in() {
  local f n=0
  for f in "$@"; do
    if grep -q 'not recorded' "$f"; then n=$((n + 1)); fi
  done
  echo "$n"
}

@test "six runs waiting on a stale lock all record their results, with no 'not recorded' warning" {
  local round i p n errs
  for round in 1 2; do
    find_shim_reset
    plant_stale
    PIDS=()
    errs=()
    for i in $(seq 1 6); do
      FIND_MODE=follow FIND_ID="r$round-$i" FIND_DEAD="$DEAD" PATH="$FS/bin:$PATH" \
        timeout -k 2 40 bash "$CR" run -- "true # stale-$round-$i" \
        > "$OUTSIDE/r$round-$i.out" 2> "$OUTSIDE/r$round-$i.err" 3>&- &
      PIDS+=("$!")
      errs+=("$OUTSIDE/r$round-$i.err")
    done
    for p in "${PIDS[@]}"; do wait "$p" || true; done
    PIDS=()
    # The device engaged: some run judged the planted lock's staleness.
    [ -e "$FS/state/leader" ]
    n=$(not_recorded_in "${errs[@]}")
    if [ "$n" -ne 0 ]; then
      echo "round $round: $n of 6 runs gave up on a lock another run had broken and re-taken"
      grep -h 'not recorded' "${errs[@]}" | head -2
      return 1
    fi
    for i in $(seq 1 6); do
      jq -e '.result == "PASS" and .exit == 0' "$OUTSIDE/r$round-$i.out"
      jq -e --arg c "true # stale-$round-$i" '[.entries[] | select(.command == $c and .result == "PASS")] | length == 1' "$LD/ledger.json"
    done
    no_lock_left
  done
}

@test "a breaker held between its stale check and its move, while another run breaks the lock and takes it, leaves that run's lock and owner in place and loses no result" {
  local ka kb theirs i apid bpid sa=0 sb=0 held=0
  ka=$(key_of "true # breaker-a")
  kb=$(key_of "true # breaker-b")
  plant_stale
  gate_arm

  # A: looks, sees the lock stale, and is held before it moves anything.
  FIND_MODE=pause FIND_ID=a PATH="$FS/bin:$PATH" \
    timeout -k 2 50 bash "$CR" run -- "true # breaker-a" \
    > "$OUTSIDE/a.out" 2> "$OUTSIDE/a.err" 3>&- &
  apid=$!
  # B: looks only once A is held, breaks the lock, takes it, and is held under it.
  FIND_MODE=after FIND_ID=b PATH="$GATE:$FS/bin:$PATH" \
    timeout -k 2 50 bash "$CR" run -- "true # breaker-b" \
    > "$OUTSIDE/b.out" 2> "$OUTSIDE/b.err" 3>&- &
  bpid=$!
  PIDS=("$apid" "$bpid")

  if ! wait_file "$FS/state/paused" 750; then
    echo "the breaker never judged the lock stale: $(cat -- "$OUTSIDE/a.err")"
    return 1
  fi
  # B takes the lock while A is held, unless A's break keeps it out (a break
  # file A holds): then nothing can move under A, and only the outcome counts.
  if wait_file "$GATE/paused" 250; then
    held=1
    theirs=$(cat -- "$LD/ledger.lock/owner")
    [ -n "$theirs" ]
    [ "$theirs" != "$DEAD" ]
    printf '%s\n' "$theirs" > "$OUTSIDE/owner.expected"
  fi

  # A goes on, from between its stale check and its move.
  touch "$FS/state/go"
  if [ "$held" -eq 1 ]; then
    for i in $(seq 1 20); do
      if [ ! -f "$LD/ledger.lock/owner" ] || ! cmp -s -- "$LD/ledger.lock/owner" "$OUTSIDE/owner.expected"; then
        echo "the held breaker moved aside the lock another run had just taken (poll $i): owner now '$(cat -- "$LD/ledger.lock/owner" 2>&1)'"
        return 1
      fi
      sleep 0.05
    done
  fi

  # B releases; both finish.
  touch "$GATE/go"
  wait "$apid" || sa=$?
  wait "$bpid" || sb=$?
  PIDS=()
  [ "$sa" -eq 0 ]
  [ "$sb" -eq 0 ]
  if [ "$(not_recorded_in "$OUTSIDE/a.err" "$OUTSIDE/b.err")" -ne 0 ]; then
    echo "a result was not recorded: $(cat -- "$OUTSIDE/a.err" "$OUTSIDE/b.err")"
    return 1
  fi
  jq -e '.result == "PASS" and .exit == 0' "$OUTSIDE/a.out"
  jq -e '.result == "PASS" and .exit == 0' "$OUTSIDE/b.out"
  jq -e --arg a "$ka" --arg b "$kb" '.entries[$a].result == "PASS" and .entries[$b].result == "PASS"' "$LD/ledger.json"
  no_lock_left
}

@test "a break file older than a minute, left by a killed breaker, does not stop the stale lock from being broken and the result recorded" {
  local k elapsed
  k=$(key_of "true # after-dead-breaker")
  plant_stale
  # The break file of a breaker killed long ago.
  printf 'dead-breaker 2\n' > "$LD/ledger.lock.break"
  touch -t 200001010000 "$LD/ledger.lock.break"

  # An outer timeout, so an endless wait is a failed assertion, not a hung suite.
  SECONDS=0
  run --separate-stderr timeout -k 2 30 bash "$CR" run -- "true # after-dead-breaker"
  elapsed=$SECONDS
  if [ "$elapsed" -ge 20 ]; then
    echo "the wait behind a dead breaker's break file did not end: ${elapsed}s, status $status"
    return 1
  fi
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .exit == 0' <<< "$output"
  if [[ "$stderr" == *"not recorded"* ]]; then
    echo "the run gave up behind a dead breaker's break file: $stderr"
    return 1
  fi
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  if [ -e "$LD/ledger.lock.break" ]; then
    echo "the break file of a killed breaker is still there, so every later stale lock waits on it"
    return 1
  fi
  no_lock_left
}

@test "a stale lock in a ledger directory that cannot be written still ends the wait within 15 s, warns, and keeps the verdict and exit code" {
  if [ "$(id -u)" -eq 0 ]; then skip "root writes a read-only directory"; fi
  local cmd="echo broken; exit 3" elapsed
  # Something recorded first, so the ledger directory exists.
  run --separate-stderr bash "$CR" run -- "$cmd"
  [ "$status" -eq 1 ]
  [ -f "$LD/ledger.json" ]

  # A dead run's lock, in a directory where no break file can be created.
  mkdir -- "$LD/ledger.lock"
  printf '%s\n' "$DEAD" > "$LD/ledger.lock/owner"
  touch -t 200001010000 "$LD/ledger.lock/owner" "$LD/ledger.lock"
  chmod a-w "$LD"

  SECONDS=0
  run --separate-stderr timeout -k 2 20 bash "$CR" run --fresh -- "$cmd"
  elapsed=$SECONDS
  chmod u+w "$LD"
  if [ "$elapsed" -ge 15 ]; then
    echo "the wait on a stale lock that cannot be broken did not end: ${elapsed}s, status $status"
    return 1
  fi
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3 and .decision == "ran"' <<< "$output"
  [[ "$stderr" == *"not recorded"* ]]
  # Nothing could be broken: the dead run's lock is still there, and no break
  # file was made.
  [ -d "$LD/ledger.lock" ]
  [ "$(cat -- "$LD/ledger.lock/owner")" = "$DEAD" ]
  [ "$(find "$LD" -maxdepth 1 -name 'ledger.lock.break' | wc -l | tr -d ' ')" -eq 0 ]
}
