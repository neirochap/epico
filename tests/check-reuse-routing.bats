#!/usr/bin/env bats
# Which runs go through `epico-check run`, which never do, and where that rule
# lives.
#
# references/check-reuse.md is the single home of the routing rules. Routed —
# repeatable checks whose PASS may be reused: the Executor's Validation runs
# (steps 4 and 5), the Auditor's Part 2 reproductions, the inline route and the
# end-of-run gates in run-mode.md, the lean route's whole check, and
# validate-mode.md. Never routed — runs that must observe a failure or run
# outside the working tree: the Test Advisor's Red runs, the deferred E2E Red
# run, the Auditor's bugfix guard on the base commit, and the final reviewer's
# clean-copy run. check-reuse.md says why.
#
# `epico-check` is matched as a whole command name: `epico-checkpoint` is a
# different command and never counts.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REF="$ROOT/references/check-reuse.md"
}

calls() {  # <text> — how many `epico-check run` invocations it holds
  printf '%s\n' "$1" | grep -cE 'epico-check run([^a-z-]|$)' || true
}

section() {  # <file> <start-regex> <stop-regex>
  awk -v s="$2" -v e="$3" '$0 ~ s { on = 1; print; next } on && $0 ~ e { exit } on { print }' "$1"
}

# --- Hostile half: what must never be routed ---

@test "the must-fail and clean-copy runs stay direct: no epico-check run in them" {
  [ -f "$REF" ]
  [ "$(calls "$(cat "$ROOT/agents/test-advisor.md")")" -eq 0 ]
  [ "$(calls "$(cat "$ROOT/agents/final-reviewer.md")")" -eq 0 ]
  e2e=$(section "$ROOT/references/run-mode.md" '^### Deferred Red for E2E' '^##+ ')
  [ -n "$e2e" ]
  [ "$(calls "$e2e")" -eq 0 ]
}

@test "check-reuse.md names each run kept out of reuse" {
  [ -f "$REF" ]
  grep -qi 'test advisor\|test-advisor' "$REF"
  grep -qi 'red' "$REF"
  grep -qi 'E2E\|end-to-end' "$REF"
  grep -qi 'base commit' "$REF"
  grep -qi 'final reviewer\|final-reviewer' "$REF"
  grep -qi 'clean copy\|clean-copy' "$REF"
}

# --- What is routed ---

@test "check-reuse.md is the home: it names epico-check run, the three modes and epico-check stats" {
  [ -f "$REF" ]
  grep -qF 'epico-check run' "$REF"
  grep -qF 'epico-check stats' "$REF"
  for m in off shadow on; do
    grep -qE "\`$m\`" "$REF" || { echo "mode $m not named"; return 1; }
  done
  grep -qF 'reuse-profile.json' "$REF"
}

@test "check-reuse.md names every routed caller" {
  [ -f "$REF" ]
  for c in executor.md auditor.md run-mode.md lean-route.md validate-mode.md; do
    grep -qF "$c" "$REF" || { echo "routed caller not named: $c"; return 1; }
  done
}

@test "the Executor runs Validation and its refactor re-runs through epico-check run" {
  steps=$(section "$ROOT/agents/executor.md" '^### Step 4' '^### Step 6')
  [ -n "$steps" ]
  [ "$(calls "$steps")" -ge 1 ]
  [[ "$steps" == *"check-reuse.md"* ]]
}

@test "the Auditor's reproductions, the lean route and validate-mode point at epico-check run" {
  for f in agents/auditor.md references/lean-route.md references/validate-mode.md; do
    [ "$(calls "$(cat "$ROOT/$f")")" -ge 1 ] || { echo "$f does not route through epico-check run"; return 1; }
  done
}

@test "run-mode.md points the inline route and the end-of-run gates at check-reuse.md" {
  [ "$(grep -c 'check-reuse\.md' "$ROOT/references/run-mode.md" || true)" -ge 2 ]
  [ "$(wc -l < "$ROOT/references/run-mode.md")" -lt 500 ]
}

@test "references name epico-check as its own command, with its own wrapper beside epico-checkpoint" {
  # The wrapper regex in bin-wrappers.bats must find epico-check as its own
  # name, and every reference that names it must have the wrapper.
  [ -x "$ROOT/bin/epico-check" ]
  [ -x "$ROOT/bin/epico-checkpoint" ]
  n=$(cd "$ROOT" && git grep -ohE '\bepico-check\b' -- references agents | grep -c . || true)
  [ "$n" -ge 1 ]
}
