#!/usr/bin/env bats
# scripts/check-reuse.sh run — the owner file, not the `mkdir`, decides who holds
# the ledger lock (R4.8, R4.11).
#
#   - uutils' `mkdir` (0.10.0, the CI image's coreutils) lets racing callers all
#     succeed, so `mkdir -- ledger.lock` alone lets several runs hold the lock at
#     once and lose each other's ledger updates, with no warning.
#   - A run holds the lock only once it has CREATED ledger.lock/owner (O_EXCL,
#     through bash's noclobber). A run that loses that create leaves the other
#     run's owner in place and goes on waiting.
#
# The `mkdir` on PATH: uutils' race at its worst. A directory that already
# exists is "created" again — exit 0 — and every other call goes to the real
# mkdir. On ledger.lock it can also act as a barrier: when armed with <n>, each
# run's FIRST mkdir of the lock waits (at most ~3 s) until <n> runs have reached
# it, so all <n> leave their mkdir within a few milliseconds of each other. That
# makes the overlap under the lock certain rather than lucky: on a lock decided
# by mkdir, all <n> hold it together. The barrier is one-shot per run, so the
# retries of a run that lost the claim meet only the always-succeeding mkdir.
# Only the runs get the shim on PATH (PATH="$SHIM/bin:$PATH"); the test itself
# uses the real mkdir.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
  SHIM="$WORK/shim"
  RPID=""
  shim_install
}

teardown() {
  # A case that failed half way must not leave a run waiting on the barrier.
  if [ -n "${SHIM:-}" ]; then rm -f -- "$SHIM/state/barrier" 2>/dev/null || true; fi
  if [ -n "${RPID:-}" ]; then kill -KILL "$RPID" 2>/dev/null || true; fi
  reuse_teardown
}

# shim_install — the racing mkdir at $SHIM/bin/mkdir; its state in $SHIM/state.
shim_install() {
  mkdir -p "$SHIM/bin" "$SHIM/state/arrived"
  command -v mkdir > "$SHIM/state/real"
  cat > "$SHIM/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
# A mkdir that "creates" a directory that already exists (uutils' race at its
# worst). Options other than a lone `--` go to the real mkdir.
bin=${0%/*}
S=${bin%/*}/state
real=$(cat -- "$S/real")
t=""
case "$#:${1:-}" in
  2:--) t=$2 ;;
  1:-*) ;;
  1:*) t=$1 ;;
esac
if [ -z "$t" ]; then exec "$real" "$@"; fi
if [ "${t##*/}" = ledger.lock ]; then
  printf '%s\n' "$PPID" >> "$S/calls"
  if [ -s "$S/barrier" ] && [ ! -e "$S/arrived/$PPID" ]; then
    : > "$S/arrived/$PPID"
    n=$(cat -- "$S/barrier" 2>/dev/null || echo 0)
    i=0
    while [ -s "$S/barrier" ] && [ "$i" -lt 150 ] &&
      [ "$(find "$S/arrived" -type f | wc -l | tr -d ' ')" -lt "$n" ]; do
      sleep 0.02
      i=$((i + 1))
    done
  fi
fi
if [ -d "$t" ]; then exit 0; fi
"$real" -- "$t" 2>/dev/null || [ -d "$t" ]
EOF
  chmod +x "$SHIM/bin/mkdir"
}

# barrier_arm <n> — the next <n> runs leave their first mkdir of the lock together.
barrier_arm() {
  rm -f -- "$SHIM/state/arrived/"*
  printf '%s\n' "$1" > "$SHIM/state/barrier"
}

barrier_disarm() { rm -f -- "$SHIM/state/barrier" "$SHIM/state/arrived/"*; }

# run_racing <command>... — one `run` per argument, all started at once, with the
# racing mkdir on PATH; waits for every one. A FAIL exits 1, which is not an
# error here.
run_racing() {
  local pids=() c p
  for c in "$@"; do
    PATH="$SHIM/bin:$PATH" bash "$CR" run -- "$c" >/dev/null 2>&1 3>&- &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
}

# no_lock_left — neither ledger.lock nor an owner file anywhere in the ledger dir.
no_lock_left() {
  if [ -e "$LD/ledger.lock" ]; then
    echo "the ledger lock was left behind: $(find "$LD/ledger.lock" | tr '\n' ' ')"
    return 1
  fi
  [ "$(find "$LD" -maxdepth 2 \( -name 'ledger.lock*' -o -name owner \) | wc -l | tr -d ' ')" -eq 0 ]
}

@test "with a mkdir that succeeds on an existing directory, twelve parallel runs on distinct keys keep twelve entries and leave no lock behind" {
  local i n cmds=()
  for i in $(seq 1 12); do cmds+=("true # claim-distinct-$i"); done
  barrier_arm 12
  run_racing "${cmds[@]}"
  barrier_disarm
  # The device really raced: every run reached the lock through the shim.
  [ "$(sort -u "$SHIM/state/calls" | wc -l | tr -d ' ')" -eq 12 ]
  [ -f "$LD/ledger.json" ]
  n=$(jq '.entries | length' "$LD/ledger.json")
  if [ "$n" -ne 12 ]; then
    echo "$n of 12 entries kept: runs that all 'won' the mkdir overwrote each other's ledger"
    return 1
  fi
  for i in $(seq 1 12); do
    jq -e --arg c "true # claim-distinct-$i" '[.entries[] | select(.command == $c and .result == "PASS")] | length == 1' "$LD/ledger.json"
  done
  no_lock_left
  # Nothing but the ledger and the shadow log: no temp file, no void marker.
  [ "$(find "$LD" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 2 ]
  jq -e . "$LD/ledger.json" > /dev/null
}

@test "with a mkdir that succeeds on an existing directory, a FAIL recorded while six PASS writers run on the same ledger wins and every writer's entry is kept" {
  local flag="$OUTSIDE/flag" kcmd round k n
  kcmd="test -f '$flag'"
  k=$(key_of "$kcmd")
  is_hash "$k"
  for round in 1 2 3; do
    # K holds a PASS; the flag goes away, so K's next run is a FAIL that must win.
    barrier_disarm
    touch "$flag"
    PATH="$SHIM/bin:$PATH" run --separate-stderr bash "$CR" run -- "$kcmd"
    [ "$status" -eq 0 ]
    jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
    rm -f "$flag"
    barrier_arm 7
    run_racing "$kcmd" "true # cw1-$round" "true # cw2-$round" "true # cw3-$round" \
      "true # cw4-$round" "true # cw5-$round" "true # cw6-$round"
    barrier_disarm
    n=$(jq -r '[.entries[] | select(.command | test("^true # cw[1-6]-'"$round"'$"))] | length' "$LD/ledger.json")
    if [ "$n" -ne 6 ]; then
      echo "round $round: $n of the 6 writers' entries kept"
      return 1
    fi
    if ! jq -e --arg k "$k" '.entries[$k].result == "FAIL"' "$LD/ledger.json"; then
      echo "round $round: the older PASS for the key survived the newer FAIL"
      return 1
    fi
    no_lock_left
  done
}

@test "a run whose mkdir reports a lock directory created that holds another run's owner file leaves that owner in place and records after it is released" {
  local lock="$LD/ledger.lock" cmd="true # after-foreign" k i
  local token="foreign-holder 4242"
  k=$(key_of "$cmd")
  is_hash "$k"
  # Another run holds the lock: its directory and its owner token.
  mkdir -p -- "$LD"
  mkdir -- "$lock"
  printf '%s\n' "$token" > "$lock/owner"
  printf '%s\n' "$token" > "$OUTSIDE/owner.expected"

  PATH="$SHIM/bin:$PATH" timeout -k 2 20 bash "$CR" run -- "$cmd" \
    > "$OUTSIDE/run.out" 2> "$OUTSIDE/run.err" 3>&- &
  RPID=$!
  # Until the run has reached the lock (its mkdir "succeeded"), at most ~10 s.
  for i in $(seq 1 200); do
    if [ -s "$SHIM/state/calls" ]; then break; fi
    sleep 0.05
  done
  [ -s "$SHIM/state/calls" ]
  # For about a second while the foreign holder keeps it, the run must not take
  # it: the owner stays byte-identical and nothing is recorded under it.
  for i in $(seq 1 20); do
    if [ ! -f "$lock/owner" ] || ! cmp -s -- "$lock/owner" "$OUTSIDE/owner.expected"; then
      echo "the run overwrote or removed another run's owner file (poll $i): $(cat -- "$lock/owner" 2>&1)"
      return 1
    fi
    if [ -f "$LD/ledger.json" ] && ! jq -e --arg k "$k" '.entries[$k] == null' "$LD/ledger.json" > /dev/null; then
      echo "the run recorded its result while another run held the lock"
      return 1
    fi
    sleep 0.05
  done
  # Still waiting, not finished and not given up.
  if ! kill -0 "$RPID" 2>/dev/null; then
    echo "the run ended while another run held the lock: $(cat -- "$OUTSIDE/run.err")"
    return 1
  fi

  # The holder releases, as ledger_unlock does: its token, then the directory.
  # The waiter may claim the empty directory in between; rmdir then refuses.
  rm -f -- "$lock/owner"
  rmdir -- "$lock" 2>/dev/null || true

  local rstatus=0
  wait "$RPID" || rstatus=$?
  RPID=""
  [ "$rstatus" -eq 0 ]
  jq -e '.result == "PASS" and .exit == 0' "$OUTSIDE/run.out"
  if grep -q 'not recorded' "$OUTSIDE/run.err"; then
    echo "the run gave up instead of recording after the release: $(cat -- "$OUTSIDE/run.err")"
    return 1
  fi
  jq -e --arg k "$k" '.entries[$k].result == "PASS"' "$LD/ledger.json"
  no_lock_left
}
