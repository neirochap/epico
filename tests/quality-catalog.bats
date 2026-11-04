#!/usr/bin/env bats
# The quality catalog, the story legend, the Quality: field and the generated
# gates — the doc contract.
#
# The surface is agent-executed prose, so every case pins a BLOCK found by a
# structural anchor and asserts a keyword inside it, case-insensitively. No
# case requires a sentence verbatim: a correct rewrite must stay green.
#
#   C1  quality-catalog.md has the three tiers, the always tier names lint,
#       types and secrets, the context tier has a Signal column, and the file
#       says activating never installs a tool
#   C2  requirements.md carries the legend section in the template and the
#       guideline that sub-tasks cite it
#   C3  tasks.md documents the Quality field, the generated gates with their
#       command, rule 12 naming cross-reference.sh, and the Fast legend
#   C4  init-mode.md writes a Quality block and its Rules call it the default
#       legend
#   C5  constitution.md's template carries a Quality section
#   C6  analyst.md's Codebase Analysis reports the catalog's signals
#   C7  phase-gates.md loads the catalog with requirements.md and tasks.md
#   C8  validate-mode.md settles a generated gate by running its command
#   C9  plain-register.md renders the legend as the checks that were run
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."

section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

has() { # has <label> <block> <keyword>
  if ! printf '%s' "$2" | grep -qi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

@test "C1: the catalog has three tiers, names the always items, carries a Signal column, and never installs" {
  f="$ROOT/references/quality-catalog.md"
  [ -f "$f" ]
  always=$(section "$f" '^## Always' '^## ')
  [ -n "$always" ]
  for w in Formatting Lint Types "Error handling" "Unit tests" Lockfile "vulnerabilities" Secrets README; do
    has "C1 always" "$always" "$w"
  done
  context=$(section "$f" '^## By context' '^## ')
  [ -n "$context" ]
  has "C1 signal column" "$context" "| Signal |"
  has "C1 context item" "$context" "Contract tests"
  request=$(section "$f" '^## On request' '^## ')
  has "C1 on request" "$request" "Fuzzing"
  chosen=$(section "$f" '^## How the set is chosen' '^## ')
  has "C1 never installs" "$chosen" "never installs"
}

@test "C2: requirements.md carries the legend section and the guideline that sub-tasks cite it" {
  f="$ROOT/references/requirements.md"
  grep -q '^## Quality Requirements' "$f"
  grep -qE '^- Q1: ' "$f"
  guide=$(section "$f" '^## Writing Guidelines' '^## ')
  has "C2 guideline" "$guide" "legend"
  has "C2 field" "$guide" "Quality:"
  has "C2 catalog" "$guide" "quality-catalog"
}

@test "C3: tasks.md documents the Quality field, the generated gates, rule 12 and the Fast legend" {
  f="$ROOT/references/tasks.md"
  fields=$(section "$f" '^### Content Fields' '^### ')
  has "C3 field row" "$fields" "| Quality |"
  gates=$(section "$f" '^### Generated Quality Gates' '^### ')
  [ -n "$gates" ]
  has "C3 one or more boxes per line" "$gates" "one or more boxes per"
  has "C3 command" "$gates" "command"
  rules=$(section "$f" '^## Rules' '^## ')
  has "C3 rule 12" "$rules" "12. [*][*]Quality coverage"
  has "C3 script" "$rules" "cross-reference.sh"
  fast=$(section "$f" '^## Fast Scale Adaptations' '^## ')
  has "C3 fast legend" "$fast" "legend"
  has "C3 fast section" "$fast" "Quality Requirements"
}

@test "C4: init-mode.md writes a Quality block, and its Rules call it the project's default legend" {
  proc=$(section "$ROOT/references/init-mode.md" '^## Procedure' '^## ')
  has "C4 block" "$proc" "## Quality"
  has "C4 never installs" "$proc" "never installs"
  rules=$(section "$ROOT/references/init-mode.md" '^## Rules' '^## ')
  has "C4 default legend" "$rules" "default legend"
}

@test "C5: the constitution template carries a Quality section" {
  f="$ROOT/references/constitution.md"
  tmpl=$(section "$f" '^## Template' '^## Guidelines')
  has "C5 section" "$tmpl" "## Quality"
  has "C5 catalog" "$tmpl" "quality-catalog"
}

@test "C6: analyst.md's Codebase Analysis reports the catalog's signals" {
  block=$(section "$ROOT/agents/analyst.md" '^## Codebase Analysis' '^## ')
  [ -n "$block" ]
  has "C6" "$block" "quality-catalog"
  has "C6 signals" "$block" "signals"
}

@test "C7: phase-gates.md loads the catalog in Phase 1 and Phase 3, Fast included" {
  block=$(section "$ROOT/references/phase-gates.md" '^## Reference Files Loaded Per Phase' '^## ')
  [ -n "$block" ]
  has "C7" "$block" "quality-catalog.md"
  has "C7 fast" "$block" "Fast mode"
}

@test "C8: validate-mode.md settles a generated gate by running its command" {
  grep -qi 'generated gate' "$ROOT/references/validate-mode.md"
  block=$(grep -i -B1 -A1 'generated gate' "$ROOT/references/validate-mode.md")
  has "C8 run" "$block" "running that command"
}

@test "C9: plain-register.md renders the legend as the checks that were run, never by number" {
  words=$(section "$ROOT/references/plain-register.md" '^## Words that stay' '^## ')
  has "C9 identifier" "$words" "Q1"
  has "C9 rendering" "$words" "checks I ran"
  has "C9 never by number" "$words" "never by number"
}

@test "the format check is scoped to the project, never sweeping .epico/" {
  # A 2026-09-26 run gated on `prettier --check .`; the run report written at
  # the end of the run then failed the gate it had already closed.
  run grep -q '^| Formatting .*prettier --check \.`' "$BATS_TEST_DIRNAME/../references/quality-catalog.md"
  [ "$status" -eq 1 ]
  grep -q "The format check covers the project's files, never \`.epico/\`" "$BATS_TEST_DIRNAME/../references/quality-catalog.md"
}
