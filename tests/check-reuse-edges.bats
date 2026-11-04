#!/usr/bin/env bats
# scripts/check-reuse.sh at its edges — the bounded files, the summary and the
# fingerprint keep their promises where a tidy fixture never goes.
#
#   - R3.4  The ledger holds at most 2000 results, the shadow log 5000 lines,
#           the OLDEST dropped first — and the result just written is never the
#           one dropped, whatever its timestamp says. A 100 KB command is
#           recorded whole. A shadow.log whose last line lost its newline loses
#           no record.
#   - R3.2  `stats` skips what is not a record, sums only numeric `secs`, and
#           for a log it cannot read gives zeros with a warning, never a crash.
#   - R4.3  `lookup` only reads: an unreadable ledger stays where it is;
#           `run` is the one that sets it aside.
#   - R2.11 A nested repository holding uncommitted content gives no
#           fingerprint (with its path in the reason); a clean one gives one.
#           A TMPDIR inside the work tree does not move the fingerprint.
#   - R5.1  A packageManager value that is not a plain tool name never becomes
#           a probe, so text from package.json never reaches `bash -c`.
#
# PATH for the packageManager cases is built from the machine's PATH with every
# toolchain binary removed, plus fake binaries the case puts there itself (the
# technique of tests/check-reuse-profile.bats).

bats_require_minimum_version 1.5.0

TOOLCHAIN="node npm npx pnpm yarn bun corepack go gofmt rustc cargo python python3 php java ruby gem deno"

setup_file() {
  SYSBIN="$BATS_FILE_TMPDIR/sysbin"
  mkdir -p "$SYSBIN"
  local d f name
  IFS=: read -r -a dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      name=${f##*/}
      [ -x "$f" ] && [ ! -d "$f" ] || continue
      case " $TOOLCHAIN " in *" $name "*) continue ;; esac
      [ -e "$SYSBIN/$name" ] || ln -s "$f" "$SYSBIN/$name"
    done
  done
  export SYSBIN
}

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  L="$(ledger_dir)"
  FAKEBIN="$WORK/fakebin"
  mkdir -p "$FAKEBIN"
}

teardown() { reuse_teardown; }

on_path() {  # <name...> — a fake binary for each, on this case's PATH
  local n
  for n in "$@"; do
    printf '#!/bin/sh\necho "%s 1.0"\n' "$n" > "$FAKEBIN/$n"
    chmod +x "$FAKEBIN/$n"
  done
}

shadow_line() {  # <at> <command> <would_reuse> <result> <secs-json>
  jq -nc --arg at "$1" --arg c "$2" --argjson w "$3" --arg r "$4" --argjson s "$5" \
    '{at: $at, command: $c, key: "k", would_reuse: $w, result: $r, secs: $s}'
}

# --- R3.4: the ledger cap never evicts the entry just written ---

@test "a full ledger whose other entries all carry a later 'at' keeps the entry just written" {
  mkdir -p "$L"
  # 2000 entries dated far in the future (k0 the oldest of them): the entry the
  # run writes now is, by its timestamp, the oldest of all 2001.
  jq -nc '{version: 1, entries: ([range(0; 2000) | {key: ("k" + tostring), value: {command: "old", result: "PASS", fingerprint: "f", at: ("9999-" + ((10000 + .) | tostring)), secs: 1}}] | from_entries)}' > "$L/ledger.json"
  [ "$(jq '.entries | length' "$L/ledger.json")" -eq 2000 ]
  run --separate-stderr cr run -- "echo edge-new"
  [ "$status" -eq 0 ]
  # The new result is there, once...
  [ "$(jq '[.entries[] | select(.command == "echo edge-new")] | length' "$L/ledger.json")" -eq 1 ]
  # ...the cap holds...
  [ "$(jq '.entries | length' "$L/ledger.json")" -eq 2000 ]
  # ...and what went is the oldest of the OTHERS.
  jq -e '.entries | has("k0") | not' "$L/ledger.json"
  jq -e '.entries | has("k1") and has("k1999")' "$L/ledger.json"
}

@test "a full ledger of older entries still drops the oldest and keeps the newest" {
  mkdir -p "$L"
  jq -nc '{version: 1, entries: ([range(0; 2000) | {key: ("k" + tostring), value: {command: "old", result: "PASS", fingerprint: "f", at: ("2001-" + ((10000 + .) | tostring)), secs: 1}}] | from_entries)}' > "$L/ledger.json"
  run --separate-stderr cr run -- "echo edge-new"
  [ "$status" -eq 0 ]
  [ "$(jq '.entries | length' "$L/ledger.json")" -eq 2000 ]
  [ "$(jq '[.entries[] | select(.command == "echo edge-new")] | length' "$L/ledger.json")" -eq 1 ]
  jq -e '.entries | has("k0") | not' "$L/ledger.json"
  jq -e '.entries | has("k1") and has("k1999")' "$L/ledger.json"
}

# --- R3.4: a command too big to pass twice as one argument ---

@test "a 100 KB command is recorded whole in the ledger and the shadow log" {
  local cmd
  # Lines of ':' — a valid shell command whose JSON escaping is twice its size.
  cmd="$(bump big)"$'\n'"$(awk 'BEGIN { for (i = 0; i < 51200; i++) print ":" }')"
  [ "${#cmd}" -gt 100000 ]
  run --separate-stderr cr run -- "$cmd"
  [ "$status" -eq 0 ]
  [ "$(counter big)" -eq 1 ]
  if grep -q 'not recorded' <<< "$stderr"; then echo "the big command was not recorded: $stderr"; return 1; fi
  [ "$(jq '.entries | length' "$L/ledger.json")" -eq 1 ]
  [ "$(jq '.entries[] | .command | length' "$L/ledger.json")" -eq "${#cmd}" ]
  [ "$(wc -l < "$L/shadow.log" | tr -d ' ')" -eq 1 ]
  [ "$(jq '.command | length' "$L/shadow.log")" -eq "${#cmd}" ]
}

# --- R3.4: a shadow.log whose last line lost its newline ---

@test "a shadow.log without a final newline loses no record" {
  mkdir -p "$L"
  {
    shadow_line 2025-01-01T00:00:00Z one false PASS 1
    shadow_line 2025-01-01T00:00:01Z two false PASS 1
    printf '%s' "$(shadow_line 2025-01-01T00:00:02Z three false PASS 1)"
  } > "$L/shadow.log"
  [ -n "$(tail -c 1 "$L/shadow.log")" ]
  run --separate-stderr cr run -- "$(bump torn)"
  [ "$status" -eq 0 ]
  # Four records, each on a line of its own, each readable.
  [ "$(wc -l < "$L/shadow.log" | tr -d ' ')" -eq 4 ]
  [ "$(jq -Rn '[inputs | fromjson? | select(type == "object")] | length' < "$L/shadow.log")" -eq 4 ]
  run --separate-stderr cr stats
  [ "$status" -eq 0 ]
  jq -e '.runs == 4' <<< "$output"
}

@test "a shadow.log that ends in a newline gets no blank line between records" {
  mkdir -p "$L"
  shadow_line 2025-01-01T00:00:00Z one false PASS 1 > "$L/shadow.log"
  run --separate-stderr cr run -- "$(bump tidy)"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$L/shadow.log" | tr -d ' ')" -eq 2 ]
  [ "$(grep -c '^$' "$L/shadow.log" || true)" -eq 0 ]
}

# --- R3.2: stats on a log that is not tidy ---

@test "stats skips lines that are not records and sums only numeric secs" {
  mkdir -p "$L"
  {
    printf 'this is not json at all\n'
    printf '\n'
    printf '{"truncated": \n'
    printf '[1, 2]\n"a string"\n42\n'
    shadow_line 2025-01-01T00:00:00Z c1 true PASS '"x"'
    shadow_line 2025-01-01T00:00:01Z c2 true PASS 3
    shadow_line 2025-01-01T00:00:02Z c3 true FAIL '[1]'
    shadow_line 2025-01-01T00:00:03Z c4 true PASS '{"a": 1}'
    shadow_line 2025-01-01T00:00:04Z c5 false PASS 100
  } > "$L/shadow.log"
  run --separate-stderr cr stats
  [ "$status" -eq 0 ]
  jq -e '.runs == 5' <<< "$output"
  jq -e '.would_reuse == 4 and .agreed == 3' <<< "$output"
  jq -e '.disagreed == [{command: "c3", at: "2025-01-01T00:00:02Z"}]' <<< "$output"
  # Of the four would-reuse runs only c2 carries a number of seconds.
  jq -e '.secs_reusable == 3' <<< "$output"
}

@test "stats on a shadow.log it cannot read: zeros, a warning, exit 0" {
  if [ "$(id -u)" -eq 0 ]; then skip "root reads any file"; fi
  mkdir -p "$L"
  shadow_line 2025-01-01T00:00:00Z c1 true PASS 3 > "$L/shadow.log"
  chmod 000 "$L/shadow.log"
  if [ -r "$L/shadow.log" ]; then skip "this account reads a mode-000 file"; fi
  run --separate-stderr cr stats
  [ "$status" -eq 0 ]
  jq -e '.runs == 0 and .would_reuse == 0 and .agreed == 0 and .secs_reusable == 0 and .disagreed == []' <<< "$output"
  grep -q 'cannot be read' <<< "$stderr"
  chmod 644 "$L/shadow.log"
}

# --- R4.3: lookup reads, run sets aside ---

@test "lookup never sets an unreadable ledger aside; run does" {
  mkdir -p "$L"
  printf 'this ledger is {not json\n' > "$L/ledger.json"
  cp "$L/ledger.json" "$WORK/ledger.before"
  run --separate-stderr cr lookup -- "echo edge-look"
  [ "$status" -eq 0 ]
  jq -e '.key != null and .last == null and .would_reuse == false' <<< "$output"
  cmp -s "$WORK/ledger.before" "$L/ledger.json"
  [ "$(find "$L" -maxdepth 1 -name 'ledger.json.unreadable-*' | wc -l | tr -d ' ')" -eq 0 ]
  # The converse: the run, which writes, does set it aside — once, intact.
  run --separate-stderr cr run -- "echo edge-look"
  [ "$status" -eq 0 ]
  [ "$(find "$L" -maxdepth 1 -name 'ledger.json.unreadable-*' | wc -l | tr -d ' ')" -eq 1 ]
  cmp -s "$WORK/ledger.before" "$(find "$L" -maxdepth 1 -name 'ledger.json.unreadable-*')"
  jq -e '.version == 1 and (.entries | length) == 1' "$L/ledger.json"
}

# --- R2.11: a nested repository holding uncommitted content ---

@test "a nested repository: clean gives a fingerprint, dirty gives none and names it" {
  local clean
  git init -q inner
  printf 'a\n' > inner/f.txt
  git -C inner add -A
  git -C inner commit -q -m inner
  # Nothing of it is added to the outer index: it is a nested repository, not a
  # registered submodule.
  clean=$(fp_now)
  is_hash "$clean"
  [ "$(fp_now)" = "$clean" ]

  # A modified tracked file.
  printf 'b\n' >> inner/f.txt
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.fingerprint == null' <<< "$output"
  jq -e '.reason | contains("uncommitted") and contains("inner")' <<< "$output"
  # `run` still runs the command and says why nothing is reused.
  run --separate-stderr cr run -- "$(bump nested)"
  [ "$status" -eq 0 ]
  [ "$(counter nested)" -eq 1 ]
  jq -e '.fingerprint == null and (.reason | contains("inner"))' <<< "$output"

  # Put it back: the fingerprint is the clean one again.
  git -C inner checkout -q -- f.txt
  [ "$(fp_now)" = "$clean" ]

  # An untracked file inside it is uncommitted content too.
  printf 'x\n' > inner/new.txt
  run --separate-stderr cr lookup -- "true"
  jq -e '.fingerprint == null' <<< "$output"
  rm -f inner/new.txt
  [ "$(fp_now)" = "$clean" ]

  # Committed, it is clean again — and the code is no longer the same code.
  printf 'c\n' >> inner/f.txt
  git -C inner add -A
  git -C inner commit -q -m "inner, changed"
  is_hash "$(fp_now)"
  [ "$(fp_now)" != "$clean" ]
}

# --- R2.11: the fingerprint's own scratch file stays out of the tree ---

@test "a TMPDIR inside the work tree leaves the fingerprint stable" {
  local base a b
  mkdir -p tmpd
  base=$(fp_now)
  is_hash "$base"
  a=$(TMPDIR="$PROJ/tmpd" bash "$CR" lookup -- true 2>/dev/null | jq -r '.fingerprint')
  b=$(TMPDIR="$PROJ/tmpd" bash "$CR" lookup -- true 2>/dev/null | jq -r '.fingerprint')
  [ "$a" = "$base" ]
  [ "$b" = "$base" ]
  [ "$(find tmpd -type f | wc -l | tr -d ' ')" -eq 0 ]
  # The converse: a real edit still moves it, with the same TMPDIR.
  printf 'echo two\n' > src/app.sh
  a=$(TMPDIR="$PROJ/tmpd" bash "$CR" lookup -- true 2>/dev/null | jq -r '.fingerprint')
  is_hash "$a"
  [ "$a" != "$base" ]
}

# --- R5.1: package.json text never becomes a command ---

@test "a packageManager value that is not a plain tool name is never a probe, and never runs" {
  on_path node npm yarn
  jq -n --arg pm "npm --version; touch $OUTSIDE/pwned; true@9.0.0" '{name: "app", packageManager: $pm}' > package.json
  run --separate-stderr env PATH="$FAKEBIN:$SYSBIN" bash "$CR" profile --detect
  [ "$status" -eq 0 ]
  [ "$(jq -c '.tools | sort' <<< "$output")" = '["node --version"]' ]
  grep -q 'not a plain tool name' <<< "$stderr"
  # The probes run when a key is built: adopt the proposal and look a command up.
  write_profile "$output"
  run --separate-stderr env PATH="$FAKEBIN:$SYSBIN" bash "$CR" lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.key != null' <<< "$output"
  [ ! -e "$OUTSIDE/pwned" ]
}

@test "a packageManager value that is a plain tool name still yields its probe" {
  on_path node pnpm yarn
  jq -n '{name: "app", packageManager: "pnpm@9.1.0+sha512.abcdef"}' > package.json
  run --separate-stderr env PATH="$FAKEBIN:$SYSBIN" bash "$CR" profile --detect
  [ "$status" -eq 0 ]
  [ "$(jq -c '.tools | sort' <<< "$output")" = '["node --version","pnpm --version"]' ]
  jq -n '{name: "app", packageManager: "yarn"}' > package.json
  run --separate-stderr env PATH="$FAKEBIN:$SYSBIN" bash "$CR" profile --detect
  [ "$(jq -c '.tools | sort' <<< "$output")" = '["node --version","yarn --version"]' ]
}
