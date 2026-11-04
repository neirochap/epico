#!/usr/bin/env bats
# scripts/check-reuse.sh: the reuse profile and the reuse key.
#
# The key is what a PASS is reused against: the command, the code fingerprint,
# the output of every profile probe, the content of every profile input (a
# gitignored file included), and the profile file itself. The profile lives at
# .epico/reuse-profile.json, {version: 1, mode, tools, inputs, never}; absent,
# invalid or of an unknown version it yields the shadow defaults — the last two
# with a warning on stderr, and the file is never modified.
#
# A probe's output is captured whatever its exit code, and each probe runs
# under `timeout "${EPICO_REUSE_PROBE_TIMEOUT:-10}"`. A probe that times out,
# or an input that exists but cannot be hashed (a directory, an unreadable
# file), leaves no key: `key` is null, `reason` says why, and the command runs.
#
# Hostile halves first: what must split the key, then what must not, then the
# plain loading cases.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  # A probe whose output this test controls: `faketool --version` prints the
  # content of $OUTSIDE/faketool.out.
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\ncat "%s/faketool.out"\n' "$OUTSIDE" > "$WORK/bin/faketool"
  chmod +x "$WORK/bin/faketool"
  printf 'faketool 1.0\n' > "$OUTSIDE/faketool.out"
  export PATH="$WORK/bin:$PATH"
}

teardown() { reuse_teardown; }

profile() {  # <tools-json> <inputs-json> [never-json]
  write_profile "$(jq -nc --argjson t "$1" --argjson i "$2" --argjson n "${3:-[]}" '{version: 1, mode: "shadow", tools: $t, inputs: $i, never: $n}')"
}

# --- Must split: each part of the environment the profile names ---

@test "a listed input changes the key although git ignores it, and the code does not move" {
  printf 'DB=one\n' > .env
  profile '[]' '[".env"]'
  k1=$(key_of "true"); f1=$(fp_now)
  is_hash "$k1"
  printf 'DB=two\n' > .env
  k2=$(key_of "true"); f2=$(fp_now)
  is_hash "$k2"
  [ "$k1" != "$k2" ]
  [ "$f1" = "$f2" ]
}

@test "two inputs that swap their contents change the key" {
  # Each input enters the key with its own path: the same two contents on the
  # other two paths are a different environment.
  printf 'A\n' > .env
  mkdir -p build
  printf 'B\n' > build/app.local.json
  profile '[]' '[".env", "build/app.local.json"]'
  k1=$(key_of "true")
  is_hash "$k1"
  printf 'B\n' > .env
  printf 'A\n' > build/app.local.json
  k2=$(key_of "true")
  [ "$k1" != "$k2" ]
}

@test "a listed input that appears where none was changes the key" {
  profile '[]' '[".env"]'
  k1=$(key_of "true")
  is_hash "$k1"
  printf 'DB=one\n' > .env
  k2=$(key_of "true")
  [ "$k1" != "$k2" ]
}

@test "a probe whose output changed changes the key" {
  profile '["faketool --version"]' '[]'
  k1=$(key_of "true")
  is_hash "$k1"
  printf 'faketool 2.0\n' > "$OUTSIDE/faketool.out"
  k2=$(key_of "true")
  [ "$k1" != "$k2" ]
}

@test "editing the profile itself changes the key" {
  profile '[]' '[]'
  k1=$(key_of "true")
  is_hash "$k1"
  profile '[]' '[]' '["some-unrelated-command"]'
  k2=$(key_of "true")
  [ "$k1" != "$k2" ]
}

@test "two different commands on the same code have two keys" {
  k1=$(key_of "true")
  k2=$(key_of "true ")
  k3=$(key_of ":")
  is_hash "$k1"
  [ "$k1" != "$k2" ]
  [ "$k1" != "$k3" ]
}

@test "a probe that exits non-zero still keys on its output" {
  # Some toolchains print their version and exit non-zero; the output is the
  # environment all the same.
  printf '#!/bin/sh\ncat "%s/failtool.out"\nexit 3\n' "$OUTSIDE" > "$WORK/bin/failtool"
  chmod +x "$WORK/bin/failtool"
  printf 'failtool 1.0\n' > "$OUTSIDE/failtool.out"
  profile '["failtool --version"]' '[]'
  k1=$(key_of "true")
  is_hash "$k1"
  [ "$(key_of "true")" = "$k1" ]
  printf 'failtool 2.0\n' > "$OUTSIDE/failtool.out"
  k2=$(key_of "true")
  is_hash "$k2"
  [ "$k1" != "$k2" ]
}

# --- No key: the environment cannot be read, so nothing is reusable ---

@test "a probe that hangs is stopped at EPICO_REUSE_PROBE_TIMEOUT: no key, a reason naming it, the command runs" {
  printf '#!/bin/sh\nexec sleep 30\n' > "$WORK/bin/hangtool"
  chmod +x "$WORK/bin/hangtool"
  profile '["hangtool --version"]' '[]'
  export EPICO_REUSE_PROBE_TIMEOUT=1
  SECONDS=0
  run --separate-stderr cr run -- "$(bump hang)"
  [ "$SECONDS" -lt 10 ]
  [ "$status" -eq 0 ]
  [ "$(counter hang)" -eq 1 ]
  jq -e '.result == "PASS" and .key == null' <<< "$output"
  jq -e '.reason | test("hangtool")' <<< "$output"
}

@test "an input that is a directory: no key, a reason, the command runs" {
  mkdir -p build/cache
  printf 'x\n' > build/cache/a
  profile '[]' '["build/cache"]'
  run --separate-stderr cr run -- "$(bump dir)"
  [ "$status" -eq 0 ]
  [ "$(counter dir)" -eq 1 ]
  jq -e '.result == "PASS" and .key == null and (.reason | length) > 0' <<< "$output"
}

@test "an input that exists but is unreadable: no key, a reason, the command runs" {
  if [ "$(id -u)" -eq 0 ]; then skip "root reads a mode-000 file"; fi
  printf 'DB=one\n' > .env
  chmod 000 .env
  profile '[]' '[".env"]'
  run --separate-stderr cr run -- "$(bump unreadable)"
  [ "$status" -eq 0 ]
  [ "$(counter unreadable)" -eq 1 ]
  jq -e '.result == "PASS" and .key == null and (.reason | length) > 0' <<< "$output"
}

# --- Must not split: what the profile does not name ---

@test "a probe whose binary is absent yields a stable key" {
  profile '["no-such-tool-for-reuse --version"]' '[]'
  k1=$(key_of "true")
  is_hash "$k1"
  [ "$(key_of "true")" = "$k1" ]
}

@test "a gitignored file the profile does not list leaves the key alone" {
  profile '[]' '[]'
  k1=$(key_of "true")
  is_hash "$k1"
  printf 'DB=two\n' > .env
  [ "$(key_of "true")" = "$k1" ]
}

@test "nothing changed: the same key twice" {
  printf 'DB=one\n' > .env
  profile '["faketool --version"]' '[".env"]'
  k1=$(key_of "true")
  is_hash "$k1"
  [ "$(key_of "true")" = "$k1" ]
}

# --- Loading the profile ---

@test "no profile: shadow defaults, and no profile file is created" {
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow"' <<< "$output"
  jq -e '.reason | test("profile absent")' <<< "$output"
  jq -e 'has("last")' <<< "$output"
  [ ! -e .epico/reuse-profile.json ]
}

@test "a profile in mode on is read as on" {
  profile_mode on
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.mode == "on"' <<< "$output"
}

@test "a profile that is not valid JSON: shadow defaults, a warning, the file untouched" {
  mkdir -p .epico
  printf '{"version": 1, "mode": "on", ' > .epico/reuse-profile.json
  cp .epico/reuse-profile.json "$WORK/profile.before"
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow"' <<< "$output"
  [ -n "$stderr" ]
  cmp -s "$WORK/profile.before" .epico/reuse-profile.json
}

@test "a profile of an unknown version saying on is never read as on" {
  write_profile '{"version": 2, "mode": "on", "tools": [], "inputs": [], "never": []}'
  cp .epico/reuse-profile.json "$WORK/profile.before"
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.mode == "shadow"' <<< "$output"
  [ -n "$stderr" ]
  cmp -s "$WORK/profile.before" .epico/reuse-profile.json
}

@test "an invalid profile never stops the check from running" {
  mkdir -p .epico
  printf 'not json\n' > .epico/reuse-profile.json
  run --separate-stderr cr run -- "$(bump p)"
  [ "$status" -eq 0 ]
  jq -e '.result == "PASS" and .mode == "shadow"' <<< "$output"
  [ "$(counter p)" -eq 1 ]
}
