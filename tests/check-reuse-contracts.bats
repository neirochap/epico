#!/usr/bin/env bats
# Producer → consumer contracts across the reuse feature.
#
#   check-reuse.sh run  →  validate-run.sh: the verdict, evidence, fingerprint
#     and decision validate-run records are the ones check-reuse produced.
#   validate-run.sh  →  run-report.sh, report.sh: every field those readers use
#     is still where they read it.
#   check-reuse.sh  ↔  hook-reuse-guard.sh: both resolve the same ledger
#     directory, from the main worktree and from a linked one.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
  vr_story
  J="$STORY/.draft/validation-run.json"
  GUARD="$PLUGIN_ROOT/scripts/hook-reuse-guard.sh"
}

teardown() { reuse_teardown; }

guard_write() {  # <file_path> <cwd>
  jq -nc --arg f "$1" --arg c "$2" '{tool_name: "Write", tool_input: {file_path: $f}, cwd: $c}' > "$WORK/payload.json"
  (cd "$2" && bash "$GUARD" < "$WORK/payload.json")
}

denies() {  # <file_path> <cwd>
  local out code=0
  out=$(guard_write "$1" "$2" 2>/dev/null) || code=$?
  if [ "$code" -eq 2 ]; then return 0; fi
  [ "$code" -eq 0 ] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<< "$out" > /dev/null 2>&1
}

# --- check-reuse → validate-run ---

@test "validate-run records the evidence and fingerprint check-reuse produced for the same command" {
  sed -i "s|\`echo ran >> $OUTSIDE/c11\`|\`printf 'alpha\\\\nomega-line\\\\n'\`|" "$STORY/tasks.md"
  grep -qF "printf 'alpha\\nomega-line\\n'" "$STORY/tasks.md"
  run --separate-stderr cr run -- "printf 'alpha\\nomega-line\\n'"
  [ "$status" -eq 0 ]
  [ "$(jq -r .evidence <<< "$output")" = "omega-line" ]
  produced_fp=$(jq -r .fingerprint <<< "$output")
  is_hash "$produced_fp"
  run --separate-stderr vr
  jq -e '.entries[] | select(.id == "1.1") | .result == "PASS" and (.detail | test("exit 0 — omega-line$"))' "$J"
  [ "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$J")" = "$produced_fp" ]
}

@test "a timeout produced by check-reuse reaches the validate-run detail" {
  sed -i "s|\`echo ran >> $OUTSIDE/c11\`|\`sleep 10\`|" "$STORY/tasks.md"
  run --separate-stderr vr --timeout 1
  jq -e '.entries[] | select(.id == "1.1") | .result == "FAIL" and (.detail | test("timed out after 1s")) and has("fingerprint")' "$J"
}

@test "mode on: the reused decision check-reuse produces is the reused flag validate-run writes" {
  profile_mode on
  run --separate-stderr vr
  c=$(sed -n 's/.*Validation: `\(echo ran >> [^`]*c11\)`.*/\1/p' "$STORY/tasks.md")
  [ -n "$c" ]
  run --separate-stderr cr lookup -- "$c"
  jq -e '.would_reuse == true' <<< "$output"
  run --separate-stderr vr
  jq -e '.entries[] | select(.id == "1.1") | .reused == true' "$J"
  [ "$(counter c11)" -eq 1 ]
}

# --- validate-run → its readers ---

@test "report.sh reads the verdict and counts every result and gate" {
  run --separate-stderr vr
  subs=$(jq '[.entries[] | select(.kind == "sub")] | length' "$J")
  gates=$(jq '[.entries[] | select(.kind == "gate")] | length' "$J")
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/report.sh" --story "$STORY"
  [ "$status" -eq 0 ]
  jq -e --argjson s "$subs" --argjson g "$gates" '.validation.verdict == "fail" and .validation.lists.results == $s and .validation.lists.gates == $g' <<< "$output"
  grep -qE '^    reused: (true|false)$' "$STORY/.draft/validation-report.yaml"
}

@test "run-report.sh lists each gate with its result from validation-run.json" {
  run --separate-stderr vr
  jq -e 'all(.entries[]; has("reused"))' "$J"
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/run-report.sh" --story "$STORY"
  [ "$status" -eq 0 ]
  grep -q '^- PASS — Secrets: ' "$STORY/.draft/run-report.md"
  grep -q '^- FAIL — All task validations pass: ' "$STORY/.draft/run-report.md"
}

# --- check-reuse ↔ hook-reuse-guard: one ledger directory ---

@test "the ledger check-reuse writes from a linked worktree is the one the guard protects, from both worktrees" {
  git worktree add -q "$WORK/linked" HEAD
  cd "$WORK/linked"
  run --separate-stderr cr run -- "true"
  [ "$status" -eq 0 ]
  written=$(find "$PROJ/.git" -name ledger.json -path '*epico/reuse*')
  [ "$(printf '%s\n' "$written" | grep -c .)" -eq 1 ]
  [ "$(dirname "$written")" = "$(ledger_dir "$WORK/linked")" ]
  [ "$(dirname "$written")" = "$(ledger_dir "$PROJ")" ]
  denies "$written" "$WORK/linked"
  denies "$written" "$PROJ"
  denies "$(dirname "$written")/shadow.log" "$WORK/linked"
}
