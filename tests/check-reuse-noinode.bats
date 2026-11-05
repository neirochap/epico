#!/usr/bin/env bats
# scripts/check-reuse.sh run — the ledger lock on a filesystem out of inodes
# (R4.10).
#
#   - A claim whose file cannot even be created (no inode left, a quota, a
#     read-only mount) is told apart from another run's claim by bash's own
#     message, never by whether a file is there afterwards: the run gives up,
#     warning "not recorded" and keeping the check's verdict, instead of waiting
#     for a breaker that does not exist.
#
# The filesystem: a user and mount namespace (`unshare -rm`) mounts a tmpfs with
# eight inodes over the ledger directory, a stale lock is planted, and the
# remaining inodes are used up, so no file or directory can be created. Skipped
# where unprivileged user namespaces are disabled.

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

@test "a stale lock on a filesystem out of inodes ends the wait, warns, and keeps the verdict and exit code" {
  mkdir -p "$LD"
  SECONDS=0
  # shellcheck disable=SC2016  # expanded by the inner bash
  run --separate-stderr unshare -rm bash -c '
    mount -t tmpfs -o size=64k,nr_inodes=8 none "$1" || exit 99
    cd "$4" || exit 99
    mkdir "$1/ledger.lock" && printf "dead 1\n" > "$1/ledger.lock/owner" && touch -t 200001010000 "$1/ledger.lock"
    i=0
    while [ "$i" -lt 50 ] && : 2>/dev/null > "$1/fill.$i"; do i=$((i + 1)); done
    timeout 30 bash "$2" run -- "$3" 2>"$5/err"
  ' _ "$LD" "$CR" "echo broken; exit 3" "$PROJ" "$OUTSIDE"
  if [ "$status" -eq 124 ]; then
    echo "the wait on a stale lock never ended with no inode left (${SECONDS}s)"
    return 1
  fi
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3 and .decision == "ran"' <<< "$output"
  grep -q 'not recorded' "$OUTSIDE/err"
}
