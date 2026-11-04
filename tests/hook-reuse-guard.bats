#!/usr/bin/env bats
# scripts/hook-reuse-guard.sh — PreToolUse guard of the reuse ledger.
#
# Only the check runner writes <git-common-dir>/epico/reuse/: a PASS in the
# ledger must stand for a run that happened. The guard denies an Edit or Write
# whose file_path resolves inside that directory, and a Bash command that
# redirects, copies, moves, tees or deletes into it — with no exemption: a
# command that also runs epico-check is denied all the same, since the write is
# still the agent's, not the runner's. A command that only runs epico-check,
# writing nowhere near the ledger, passes. It allows everything else, and on
# its own error it lets the call through. A deny names the rule: the ledger is written only by
# `epico-check run`.
#
# A deny is either form a PreToolUse hook may use — exit 2, or exit 0 with
# hookSpecificOutput.permissionDecision "deny".
#
# Hostile halves first: near-miss paths that are NOT the ledger must pass, and
# other spellings of the ledger must be caught.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  GUARD="$PLUGIN_ROOT/scripts/hook-reuse-guard.sh"
  L="$(ledger_dir)"
}

teardown() { reuse_teardown; }

guard_file() {  # <tool> <file_path> [cwd]
  jq -nc --arg t "$1" --arg f "$2" --arg c "${3:-$PWD}" '{tool_name: $t, tool_input: {file_path: $f}, cwd: $c}' > "$WORK/payload.json"
  run --separate-stderr bash "$GUARD" < "$WORK/payload.json"
}

guard_bash() {  # <command> [cwd]
  jq -nc --arg x "$1" --arg c "${2:-$PWD}" '{tool_name: "Bash", tool_input: {command: $x}, cwd: $c}' > "$WORK/payload.json"
  run --separate-stderr bash "$GUARD" < "$WORK/payload.json"
}

denied() {  # the last guard call refused the tool call
  if [ "$status" -eq 2 ]; then return 0; fi
  [ "$status" -eq 0 ] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<< "$output" > /dev/null 2>&1
}

allowed() {  # the last guard call let the tool call through
  [ "$status" -eq 0 ] || return 1
  if [ -z "$output" ]; then return 0; fi
  jq -e '(.hookSpecificOutput.permissionDecision // "allow") != "deny"' <<< "$output" > /dev/null
}

deny_message() { printf '%s\n%s' "$stderr" "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<< "$output" 2>/dev/null)"; }

# --- Must pass: paths and commands that only look like the ledger ---

@test "Write: near-miss paths outside the ledger directory pass, the ledger itself does not" {
  mkdir -p "$L"
  for p in "$PROJ/epico/reuse/ledger.json" "$PROJ/.git/epico/reuse-old/ledger.json" \
           "$PROJ/.git/epico/reusex/ledger.json" "$PROJ/.git/epico/ledger.json" \
           "$PROJ/src/reuse/ledger.json" "$PROJ/.epico/reuse-profile.json"; do
    guard_file Write "$p"
    allowed || { echo "denied a path outside the ledger: $p"; return 1; }
  done
  guard_file Write "$L/ledger.json"
  denied
}

@test "Bash: reading the ledger, and writing elsewhere, pass; writing into it does not" {
  for c in "cat .git/epico/reuse/ledger.json" "jq . .git/epico/reuse/ledger.json" "ls -la .git/epico/reuse/" \
           "echo hi > notes.txt" "cp a b" "echo x > .git/epico/reuse-old/ledger.json" \
           "echo x > src/epico/reuse/notes.txt" "epico-check run -- make test" \
           "bash scripts/check-reuse.sh stats" "epico-check stats | jq ."; do
    guard_bash "$c"
    allowed || { echo "denied a harmless command: $c"; return 1; }
  done
  guard_bash "echo '{}' > .git/epico/reuse/ledger.json"
  denied
}

# --- Must be caught: every spelling of the ledger directory ---

@test "Edit and Write into the ledger directory are denied, naming epico-check run" {
  mkdir -p "$L"
  for t in Edit Write; do
    for f in ledger.json shadow.log; do
      guard_file "$t" "$L/$f"
      denied || { echo "$t $f was let through"; return 1; }
      [[ "$(deny_message)" == *"epico-check run"* ]]
    done
  done
}

@test "a ledger path spelled relative, with .., or through a symlink is denied" {
  mkdir -p "$L"
  guard_file Write ".git/epico/reuse/ledger.json" "$PROJ"
  denied
  guard_file Write "src/../.git/epico/reuse/ledger.json" "$PROJ"
  denied
  ln -s "$L" "$WORK/alias"
  guard_file Write "$WORK/alias/ledger.json" "$PROJ"
  denied
}

@test "a Write into a ledger directory that does not exist yet is denied" {
  [ ! -e "$L" ]
  guard_file Write "$L/ledger.json"
  denied
}

@test "from a linked worktree, the shared ledger in the main repository is denied" {
  git worktree add -q "$WORK/linked" HEAD
  cd "$WORK/linked"
  guard_file Write "$L/ledger.json" "$WORK/linked"
  denied
  guard_bash "rm -f '$L/ledger.json'" "$WORK/linked"
  denied
}

@test "Bash: a redirect, cp, mv, tee or rm into the ledger directory is denied" {
  for c in "echo '{}' > .git/epico/reuse/ledger.json" \
           "printf x >> $L/shadow.log" \
           "cp /tmp/forged.json .git/epico/reuse/ledger.json" \
           "mv forged.json $L/ledger.json" \
           "jq . forged.json | tee .git/epico/reuse/ledger.json" \
           "rm -f .git/epico/reuse/ledger.json" \
           "rm -rf $L"; do
    guard_bash "$c"
    denied || { echo "let through: $c"; return 1; }
  done
}

@test "Bash: running epico-check exempts no write into the ledger directory" {
  # The exemption a guard might grant the runner by name is the hole: chained
  # beside it, or redirected from it, the write is the agent's.
  guard_bash "epico-check run -- make test"
  allowed
  for c in "cp /tmp/forged.json $L/ledger.json && epico-check stats" \
           "epico-check stats > $L/x" \
           "epico-check run -- true; cp /tmp/forged.json .git/epico/reuse/ledger.json" \
           "bash scripts/check-reuse.sh stats | tee .git/epico/reuse/ledger.json"; do
    guard_bash "$c"
    denied || { echo "exempted by the runner's name: $c"; return 1; }
  done
}

# --- Fails open on its own error ---

@test "malformed input, an empty payload, or a cwd outside git: the call goes through" {
  run --separate-stderr bash "$GUARD" <<< "not json"
  [ "$status" -eq 0 ]
  run --separate-stderr bash "$GUARD" < /dev/null
  [ "$status" -eq 0 ]
  mkdir -p "$WORK/plain"
  cd "$WORK/plain"
  guard_file Write "$WORK/plain/epico/reuse/ledger.json" "$WORK/plain"
  allowed
  # The same guard, given a well-formed payload in the repository, still bites.
  cd "$PROJ"
  guard_file Write "$L/ledger.json"
  denied
}

@test "other tools pass untouched" {
  mkdir -p "$L"
  guard_file Read "$L/ledger.json"
  allowed
  guard_file Write "$L/ledger.json"
  denied
}

# --- Registration ---

@test "hooks.json registers the guard on PreToolUse for Edit|Write and for Bash" {
  H="$PLUGIN_ROOT/hooks/hooks.json"
  [ "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write") | .hooks[].command | select(test("hook-reuse-guard\\.sh"))] | length' "$H")" -ge 1 ]
  [ "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command | select(test("hook-reuse-guard\\.sh"))] | length' "$H")" -ge 1 ]
}
