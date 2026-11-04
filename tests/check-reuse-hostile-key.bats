#!/usr/bin/env bats
# scripts/check-reuse.sh: hostile probes, profiles and inputs.
#
# Contract (R2.5, R2.11, R2.13, R4.4): no probe, profile or input can leave the
# reuse key unchanged when the environment changed, and none can break the
# runner. Where the environment cannot be read, there is NO key (null, with a
# reason) — never a stable placeholder that would hide a real change.
#
#   - the key changes when a probe's output changes, whatever the probe's shape
#     (huge output, an environment-variable prefix, a relative path);
#   - the key does not depend on the directory the check is started from;
#   - no `timeout` binary: no key, and the reason names it;
#   - a probe past EPICO_REUSE_PROBE_TIMEOUT is stopped (0 means the default 10);
#   - an input that is not a regular file (a FIFO) gives no key and never hangs;
#   - a profile holding several JSON documents, or a tool or input holding a
#     newline, is invalid: shadow defaults, a warning, the file untouched.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  # `faketool --version` prints the content of $OUTSIDE/faketool.out.
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\ncat "%s/faketool.out"\n' "$OUTSIDE" > "$WORK/bin/faketool"
  chmod +x "$WORK/bin/faketool"
  printf 'faketool 1.0\n' > "$OUTSIDE/faketool.out"
  export PATH="$WORK/bin:$PATH"
}

teardown() { reuse_teardown; }

profile() {  # <tools-json> <inputs-json> [mode]
  write_profile "$(jq -nc --argjson t "$1" --argjson i "$2" --arg m "${3:-shadow}" \
    '{version: 1, mode: $m, tools: $t, inputs: $i, never: []}')"
}

# invalid_profile_is_ignored — the profile now on disk must be read as invalid:
# shadow defaults (never the mode it says), a warning, the file untouched.
invalid_profile_is_ignored() {
  cp .epico/reuse-profile.json "$WORK/profile.before"
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow"' <<< "$output"
  jq -e '.reason | test("profile invalid")' <<< "$output"
  [ -n "$stderr" ]
  cmp -s "$WORK/profile.before" .epico/reuse-profile.json
}

# --- Probe output: huge, prefixed, relative ---

@test "200 KB of probe output still gives a key, and the key follows the output" {
  # The output enters the key as a hash: it never meets the argument-size limit.
  printf '#!/bin/sh\nhead -c 200000 /dev/zero | tr "\\0" x\ncat "%s/big.tail"\n' "$OUTSIDE" > "$WORK/bin/bigtool"
  chmod +x "$WORK/bin/bigtool"
  printf 'tail one\n' > "$OUTSIDE/big.tail"
  profile '["bigtool --version"]' '[]'
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  k1=$(jq -r '.key' <<< "$output")
  is_hash "$k1"
  [ "$(key_of "true")" = "$k1" ]
  printf 'tail two\n' > "$OUTSIDE/big.tail"
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  k2=$(jq -r '.key' <<< "$output")
  is_hash "$k2"
  [ "$k1" != "$k2" ]
}

@test "a probe with an environment prefix changes the key when the tool's output changes" {
  # `VAR=1 faketool --version`: its first word is shell syntax, not a binary.
  # Calling it "absent" would freeze the key whatever the tool printed.
  profile '["REUSE_PROBE_VAR=1 faketool --version"]' '[]'
  k1=$(key_of "true")
  is_hash "$k1"
  [ "$(key_of "true")" = "$k1" ]
  printf 'faketool 2.0\n' > "$OUTSIDE/faketool.out"
  k2=$(key_of "true")
  is_hash "$k2"
  [ "$k1" != "$k2" ]
}

@test "a relative probe gives the same key from the top level and from a subdirectory" {
  printf '#!/bin/sh\ncat "%s/rel.out"\n' "$OUTSIDE" > probe.sh
  chmod +x probe.sh
  printf 'rel one\n' > "$OUTSIDE/rel.out"
  profile '["./probe.sh"]' '[]'
  k_top=$(key_of "true")
  k_sub=$(cd src && key_of "true")
  is_hash "$k_top"
  [ "$k_top" = "$k_sub" ]
  # ...and the key from the subdirectory still follows the probe's output.
  printf 'rel two\n' > "$OUTSIDE/rel.out"
  k_sub2=$(cd src && key_of "true")
  is_hash "$k_sub2"
  [ "$k_sub" != "$k_sub2" ]
  [ "$k_sub2" = "$(key_of "true")" ]
}

# --- No timeout binary: the probe cannot be bounded, so no key ---

@test "no timeout binary: no key, a reason naming timeout, however the tool's output moves" {
  NOTIMEOUT="$WORK/notimeout"
  mkdir -p "$NOTIMEOUT"
  for t in bash sh git jq cat rm mktemp head awk cp dirname basename printf env tr sed \
    date mkdir mv find stat wc tail sleep grep sort uname; do
    if p=$(type -P "$t"); then ln -s "$p" "$NOTIMEOUT/$t"; fi
  done
  ln -s "$WORK/bin/faketool" "$NOTIMEOUT/faketool"
  if PATH="$NOTIMEOUT" command -v timeout >/dev/null 2>&1; then
    echo "the restricted PATH still finds a timeout binary"
    return 1
  fi
  profile '["faketool --version"]' '[]'
  run --separate-stderr env PATH="$NOTIMEOUT" "$(type -P bash)" "$CR" lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.key == null' <<< "$output"
  jq -e '.reason | test("timeout")' <<< "$output"
  jq -e '.fingerprint != null' <<< "$output"
  # A different tool output leaves the key just as absent: nothing is frozen.
  printf 'faketool 2.0\n' > "$OUTSIDE/faketool.out"
  run --separate-stderr env PATH="$NOTIMEOUT" "$(type -P bash)" "$CR" lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.key == null' <<< "$output"
  jq -e '.reason | test("timeout")' <<< "$output"
}

# --- Profile: several documents, newlines ---

@test "a profile of two documents, a version-2 one saying on first, is never read as on" {
  printf '%s\n%s\n' \
    '{"version": 2, "mode": "on", "tools": [], "inputs": [], "never": []}' \
    '{"version": 1, "mode": "shadow", "tools": [], "inputs": [], "never": []}' \
    > "$WORK/two.json"
  mkdir -p .epico
  cp "$WORK/two.json" .epico/reuse-profile.json
  invalid_profile_is_ignored
}

@test "a profile of two valid documents is invalid, whichever order they come in" {
  mkdir -p .epico
  printf '%s\n%s\n' \
    '{"version": 1, "mode": "on", "tools": [], "inputs": [], "never": []}' \
    '{"version": 1, "mode": "shadow", "tools": [], "inputs": [], "never": []}' \
    > .epico/reuse-profile.json
  invalid_profile_is_ignored
  printf '%s\n%s\n' \
    '{"version": 1, "mode": "shadow", "tools": [], "inputs": [], "never": []}' \
    '{"version": 1, "mode": "on", "tools": [], "inputs": [], "never": []}' \
    > .epico/reuse-profile.json
  invalid_profile_is_ignored
}

@test "a tool holding a newline makes the profile invalid, not two probes" {
  profile '["faketool --version\nfaketool --other"]' '[]' on
  invalid_profile_is_ignored
}

@test "an input holding a newline makes the profile invalid, not two paths" {
  profile '[]' '[".env\nbuild/x"]' on
  invalid_profile_is_ignored
}

# --- Inputs: a FIFO must not hang the runner ---

@test "a FIFO input gives no key, a reason, and does not hang" {
  mkfifo build-fifo
  profile '[]' '["build-fifo"]'
  SECONDS=0
  run --separate-stderr timeout -k 1 8 bash "$CR" lookup -- "true"
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 8 ]
  jq -e '.key == null' <<< "$output"
  jq -e '.reason | test("not a regular file")' <<< "$output"
  jq -e '.reason | test("build-fifo")' <<< "$output"
}

# --- EPICO_REUSE_PROBE_TIMEOUT=0 means the default, not "no limit" ---

@test "EPICO_REUSE_PROBE_TIMEOUT=0 means the default 10: a slow probe is stopped, no key, named" {
  printf '#!/bin/sh\nexec sleep 14\n' > "$WORK/bin/slowtool"
  chmod +x "$WORK/bin/slowtool"
  profile '["slowtool --version"]' '[]'
  export EPICO_REUSE_PROBE_TIMEOUT=0
  SECONDS=0
  run --separate-stderr timeout -k 1 20 bash "$CR" lookup -- "true"
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 14 ]
  jq -e '.key == null' <<< "$output"
  jq -e '.reason | test("slowtool")' <<< "$output"
}
