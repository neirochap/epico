#!/usr/bin/env bats
# scripts/check-reuse.sh run — the ledger lock on a full filesystem (R4.10).
#
#   - A claim whose file is created but whose token cannot be written (no space
#     left) is this run's own: the file is removed again and the run gives up,
#     warning "not recorded" and keeping the check's verdict — it never reads its
#     own empty file as another run's claim and waits on it for ever.
#   - That holds for the owner file of the lock and for the break file of a
#     stale lock alike, and nothing of the claim is left behind.
#
# The full filesystem: a user and mount namespace (`unshare -rm`) mounts an
# 8 KiB tmpfs over the ledger directory and fills it, so files can still be
# created but nothing can be written to them. Skipped where unprivileged user
# namespaces are disabled.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  LD="$(ledger_dir)"
  if ! unshare -rm true 2>/dev/null; then skip "no unprivileged user and mount namespaces"; fi
}

teardown() {
  reuse_teardown
}

# full_run <setup> <command> — in a fresh namespace: an 8 KiB tmpfs over the
# ledger directory, <setup> evaluated in it, the rest filled, then one
# check-reuse run of <command> under a 30 s outer timeout. Its JSON goes to
# stdout, its stderr to $OUTSIDE/err, and what is left of the lock after it to
# $OUTSIDE/left (the tmpfs is gone once the namespace ends).
full_run() {
  mkdir -p "$LD"
  # shellcheck disable=SC2016  # expanded by the inner bash
  unshare -rm bash -c '
    mount -t tmpfs -o size=8k none "$1" || exit 99
    cd "$5" || exit 99
    eval "$2"
    dd if=/dev/zero of="$1/fill" bs=1k count=64 2>/dev/null || true
    rc=0
    timeout 30 bash "$3" run -- "$4" 2>"$6/err" || rc=$?
    find "$1" -mindepth 1 \( -name "ledger.lock*" -o -name owner \) > "$6/left"
    exit "$rc"
  ' _ "$LD" "$1" "$CR" "$2" "$PROJ" "$OUTSIDE"
}

@test "a stale lock on a full filesystem ends the wait, warns, and keeps the verdict and exit code" {
  # shellcheck disable=SC2016  # evaluated inside the namespace
  local stale='mkdir "$1/ledger.lock" && printf "dead 1\n" > "$1/ledger.lock/owner" && touch -t 200001010000 "$1/ledger.lock"'
  SECONDS=0
  run --separate-stderr full_run "$stale" "echo broken; exit 3"
  if [ "$status" -eq 124 ]; then
    echo "the wait on a stale lock never ended on a full filesystem (${SECONDS}s)"
    return 1
  fi
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3 and .decision == "ran"' <<< "$output"
  grep -q 'not recorded' "$OUTSIDE/err"
  # The stale lock is still there; no break file of ours is.
  [ "$(grep -c 'ledger.lock.break' "$OUTSIDE/left")" -eq 0 ]
}

@test "a claim on a full filesystem gives up at once and leaves no lock or owner file behind" {
  SECONDS=0
  run --separate-stderr full_run ":" "true # full"
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .exit == 0' <<< "$output"
  grep -q 'not recorded' "$OUTSIDE/err"
  if [ -s "$OUTSIDE/left" ]; then
    echo "left behind: $(tr '\n' ' ' < "$OUTSIDE/left")"
    return 1
  fi
  # Its own empty owner file is not another run's lock: no 5 s wait on it.
  [ "$SECONDS" -lt 4 ]
}
