#!/usr/bin/env bats
# Gate guidance: one gate per target, and no gate that defeats a cache.
#
# references/quality-catalog.md directs a check over several targets to one
# gate line per target, sharing the legend's Qn, each with distinct text before
# the colon — a per-target line is what can be reused one by one. It never
# tells the author to loop over targets in one command. A subsection says a
# gate never switches a tool's own result cache off, naming each tool together
# with its flag; `go test -count=1` is for tests that read external state;
# incremental modes are preferred; and no gate runs a command another gate of
# the same story already runs. references/tasks.md's Generated Quality Gates
# says one or more boxes per legend line, one per target.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CAT="$ROOT/references/quality-catalog.md"
  TASKS="$ROOT/references/tasks.md"
}

pair_lines() {  # <tool> <flag> — lines naming the tool (any case) and the flag together
  awk -v t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" -v f="$2" \
    'index(tolower($0), t) && index($0, f) { n++ } END { print n + 0 }' "$CAT"
}

# --- Hostile halves ---

@test "the one-command loop over targets is gone from the catalog" {
  [ "$(grep -cF 'one command that loops over them' "$CAT" || true)" -eq 0 ]
  [ "$(grep -cF 'for t in a b;' "$CAT" || true)" -eq 0 ]
}

@test "a cache flag is never named bare: every line with --no-cache names jest beside it" {
  # `--no-cache` on a package manager is not a test cache; the guidance names
  # tool and flag together so neither reads as the other.
  [ "$(pair_lines jest --no-cache)" -ge 1 ]
  bare=$(awk 'index($0, "--no-cache") && !index(tolower($0), "jest") { n++ } END { print n + 0 }' "$CAT")
  [ "$bare" -eq 0 ]
}

@test "per-target gates share one Qn and differ before the colon" {
  # Every example gate line, grouped by its Qn: some Qn must carry two lines
  # whose text before the colon differs.
  # Inline or on their own line, each example is `- [ ] Qn — <text>: <command>`.
  shared=$(grep -oE '\- \[ \] Q[0-9]+ — [^:`]+:' "$CAT" | sed -E 's/^- \[ \] //' |
    awk '{ q = $1; if (!seen[$0]++) n[q]++ } END { m = 0; for (q in n) if (n[q] > m) m = n[q]; print m }')
  [ "$shared" -ge 2 ]
}

# --- The new guidance ---

@test "each tool's cache-off flag is named with the tool" {
  [ "$(pair_lines turbo --force)" -ge 1 ] || [ "$(pair_lines turbo TURBO_FORCE)" -ge 1 ]
  [ "$(pair_lines nx --skip-nx-cache)" -ge 1 ]
  [ "$(pair_lines jest --no-cache)" -ge 1 ]
  [ "$(pair_lines pytest --cache-clear)" -ge 1 ]
  [ "$(pair_lines gradle --rerun-tasks)" -ge 1 ]
  [ "$(pair_lines gradle --no-build-cache)" -ge 1 ]
}

@test "go test -count=1 is reserved for tests that read external state" {
  [ "$(awk 'index($0, "go test -count=1") && index($0, "external state") { n++ } END { print n + 0 }' "$CAT")" -ge 1 ]
}

@test "incremental modes are preferred, and no gate re-runs another gate's command" {
  grep -qi 'incremental' "$CAT"
  grep -qi 'stryker' "$CAT"
  grep -qi 'another gate' "$CAT"
}

@test "the first backtick span is still the whole command validate runs" {
  grep -qF 'The first backtick span of a gate is the whole command validate runs' "$CAT"
  grep -qF 'no `<placeholder>`' "$CAT"
  [ "$(grep -cF 'one command that loops over them' "$CAT" || true)" -eq 0 ]
}

@test "tasks.md: one or more boxes per legend line, one per target" {
  gates=$(awk '/^### Generated Quality Gates/ { on = 1; next } on && /^### / { exit } on { print }' "$TASKS")
  [ -n "$gates" ]
  [[ "$gates" == *"one or more boxes per"* ]]
  [[ "$gates" == *"one per target"* ]]
}
