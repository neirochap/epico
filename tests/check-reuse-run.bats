#!/usr/bin/env bats
# scripts/check-reuse.sh run [--fresh] [--timeout <s>] -- <command>
#
# The run semantics validate-run.sh had, moved intact: the command runs in its
# own session under a timeout, its output goes to a file (never a pipe), the
# session is killed once it returns, and the evidence is the last output line —
# or the summed cargo totals. Exit 0 = PASS, 1 = FAIL, 2 = bad usage; a timeout
# is a FAIL with evidence "timed out after <s>s". One JSON line on stdout:
# mode, decision, would_reuse, result, exit, evidence, secs, fingerprint, key,
# reason. The command's own output never reaches that stdout.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
}

teardown() { reuse_teardown; }

# --- The verdict is the command's, never the reuse layer's ---

@test "a failing command is FAIL with exit 1, and its own code is reported" {
  run --separate-stderr cr run -- "echo broken; exit 3"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .exit == 3 and .decision == "ran"' <<< "$output"
  jq -e '.evidence == "broken"' <<< "$output"
}

@test "a command that prints PASS but fails is still FAIL" {
  run --separate-stderr cr run -- "echo PASS; false"
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL"' <<< "$output"
}

@test "a hanging command fails at its timeout, with the timeout as evidence" {
  SECONDS=0
  run --separate-stderr cr run --timeout 1 -- "sleep 10"
  [ "$SECONDS" -lt 8 ]
  [ "$status" -eq 1 ]
  jq -e '.result == "FAIL" and .evidence == "timed out after 1s"' <<< "$output"
}

@test "a passing command is PASS with exit 0, the last output line as evidence" {
  run --separate-stderr cr run -- "printf 'first\n\nlast line\n\n'"
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .exit == 0 and .decision == "ran"' <<< "$output"
  jq -e '.evidence == "last line"' <<< "$output"
}

@test "the command's output never reaches stdout: exactly one JSON line" {
  run --separate-stderr cr run -- "echo one; echo two; echo three >&2"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  jq -e '.result == "PASS"' <<< "$output"
}

@test "the JSON carries every contract key with its type" {
  run --separate-stderr cr run -- "true"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow"' <<< "$output"
  jq -e '.decision == "ran" and (.would_reuse | type) == "boolean"' <<< "$output"
  jq -e '(.secs | type) == "number" and (.evidence | type) == "string" and (.reason | type) == "string"' <<< "$output"
  is_hash "$(jq -r .fingerprint <<< "$output")"
  is_hash "$(jq -r .key <<< "$output")"
}

@test "a command that backgrounds a server returns, and the server is killed" {
  SECONDS=0
  run --separate-stderr cr run --timeout 20 -- "sleep 30 & echo \$! > '$OUTSIDE/server.pid'"
  [ "$SECONDS" -lt 10 ]
  [ "$status" -eq 0 ]
  [ -s "$OUTSIDE/server.pid" ]
  # Gone, or a zombie: a container whose PID 1 never reaps keeps the killed
  # process in the table.
  state=$(awk '{print $3}' "/proc/$(cat "$OUTSIDE/server.pid")/stat" 2>/dev/null || true)
  [ -z "$state" ] || [ "$state" = Z ]
}

@test "cargo's per-binary summaries are added up, not cut to the doc-test line" {
  cat > "$OUTSIDE/fake-cargo.sh" <<'SH'
#!/usr/bin/env bash
printf 'running 30 tests\ntest result: ok. 30 passed; 0 failed; 0 ignored\n\nrunning 3 tests\ntest result: ok. 3 passed; 0 failed; 0 ignored\n\n   Doc-tests app\nrunning 0 tests\ntest result: ok. 0 passed; 0 failed; 0 ignored\n'
SH
  chmod +x "$OUTSIDE/fake-cargo.sh"
  run --separate-stderr cr run -- "'$OUTSIDE/fake-cargo.sh'"
  [ "$status" -eq 0 ]
  jq -e '.evidence | test("33 passed, 0 failed")' <<< "$output"
}

@test "a directory that is not a git work tree still runs the command, and says why nothing is reusable" {
  mkdir -p "$WORK/plain"
  cd "$WORK/plain"
  run --separate-stderr cr run -- "$(bump plain)"
  [ "$status" -eq 0 ]
  [ "$(counter plain)" -eq 1 ]
  jq -e '.result == "PASS" and .decision == "ran" and .fingerprint == null' <<< "$output"
  jq -e '(.reason | length) > 0' <<< "$output"
}

# --- Usage: exit 2, no JSON, nothing run ---

@test "usage errors exit 2, print no JSON and run nothing" {
  run --separate-stderr cr run
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr run --
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr run --timeout abc -- "$(bump u)"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr run --no-such-flag -- "$(bump u)"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr run "$(bump u)"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$(counter u)" -eq 0 ]
}
