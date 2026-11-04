#!/usr/bin/env bats
# Two gate lines that share one Qn — one per target.
#
# `- [ ] Q5 — Unit tests (api): …` and `- [ ] Q5 — Unit tests (web): …` are two
# gates of one legend item. The story validates with no error; close-subtask.sh
# closes each by its own text prefix and leaves the other open; a prefix both
# lines answer to is refused and writes nothing; validate-run settles them as
# two entries and re-runs one of them alone.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epico/stories/004-ledger"
  mkdir -p "$STORY"
  git -C "$PROJ" init -q
  git -C "$PROJ" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m "feat(004): ledger core"
  cat > "$STORY/story.md" <<'EOF'
---
story: ledger
type: feature
scale: standard
engineering: project
status: in-progress
version: 1
created: 2026-11-04
---

# Story - Ledger

## Introduction
A fixture story whose unit tests run over two targets.

## Requirements

### R1. Record
#### Acceptance Criteria
- R1.1: WHEN an entry is saved THE SYSTEM SHALL keep it

## Quality Requirements

- Q1: Supported and declared runtime — `true` exits 0
- Q2: Secrets — `true` reports no leaks
- Q3: README — `true` exits 0
- Q4: Dependency vulnerabilities (SCA) — `true` reports none
- Q5: Unit tests — one gate per target: `true` for each
- Q6: Data integrity — `true` exits 0
EOF
  cat > "$STORY/tasks.md" <<'EOF'
---
story: ledger
type: feature
scale: standard
engineering: project
status: in-progress
version: 1
created: 2026-11-04
---

# Implementation Plan - Ledger

## Task List

- [ ] 1 - Record
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None_
  - [ ] 1.1 - Save an entry
    - Requirements: R1.1
    - Quality: Q1, Q2, Q3, Q4, Q5, Q6
    - Validation: `true`
  - Commit: "feat(004): ledger core"

## Quality Gates

- [ ] All task validations pass
- [ ] Q1 — Supported and declared runtime: `true` exits 0
- [ ] Q2 — Secrets: `true` reports no leaks
- [ ] Q3 — README: `true` exits 0
- [ ] Q4 — Dependency vulnerabilities (SCA): `true` reports none
- [ ] Q5 — Unit tests (api): `echo ran >> @OUT@/api`
- [ ] Q5 — Unit tests (web): `echo ran >> @OUT@/web`
- [ ] Q6 — Data integrity: `true` exits 0
EOF
  mkdir -p "$WORK/outside"
  sed -i "s|@OUT@|$WORK/outside|g" "$STORY/tasks.md"
  cd "$PROJ" || return 1
}

teardown() { cd /; rm -rf "$WORK"; }

close() { run --separate-stderr bash "$PLUGIN_ROOT/scripts/close-subtask.sh" "$STORY" "$@"; }
runs() { if [ -f "$WORK/outside/$1" ]; then wc -l < "$WORK/outside/$1" | tr -d ' '; else echo 0; fi; }

# --- Hostile halves ---

@test "a prefix both Q5 lines answer to is refused, and nothing is written" {
  cp "$STORY/tasks.md" "$WORK/tasks.before"
  close "gate:Q5 — Unit tests"
  [ "$status" -eq 1 ]
  jq -e '.box == null and (.reason | length) > 0' <<< "$output"
  cmp -s "$WORK/tasks.before" "$STORY/tasks.md"
}

@test "closing one target leaves the other open, in either order" {
  close "gate:Q5 — Unit tests (web)"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- \[x\] Q5 — Unit tests (web):' "$STORY/tasks.md")" -eq 1 ]
  [ "$(grep -c '^- \[ \] Q5 — Unit tests (api):' "$STORY/tasks.md")" -eq 1 ]
  close "gate:Q5 — Unit tests (api)"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- \[x\] Q5 — Unit tests (' "$STORY/tasks.md")" -eq 2 ]
}

@test "epico-close closes both targets in one call, each by its own prefix" {
  run --separate-stderr bash "$PLUGIN_ROOT/bin/epico-close" "$STORY" "gate:Q5 — Unit tests (api)" "gate:Q5 — Unit tests (web)"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^{' <<< "$output")" -eq 2 ]
  [ "$(grep -c '^- \[x\] Q5 — Unit tests (' "$STORY/tasks.md")" -eq 2 ]
  # The five other Qn gates are untouched.
  [ "$(grep -c '^- \[ \] Q[0-9]' "$STORY/tasks.md")" -eq 5 ]
}

# --- The story is valid ---

@test "the story validates with no error, strict and cross-referenced included" {
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --strict
  [ "$status" -eq 0 ]
  jq -e '.errors == 0 and .status == "pass"' <<< "$output"
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$STORY" --cross-ref --strict
  [ "$status" -eq 0 ]
  jq -e '.errors == 0 and .status == "pass"' <<< "$output"
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/cross-reference.sh" "$STORY"
  [ "$status" -eq 0 ]
}

@test "validate-run settles the two Q5 gates as two entries, and re-runs one alone" {
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/validate-run.sh" --story "$STORY"
  J="$STORY/.draft/validation-run.json"
  [ "$(jq '[.entries[] | select(.kind == "gate" and (.id | startswith("Q5 — Unit tests (")))] | length' "$J")" -eq 2 ]
  [ "$(runs api)" -eq 1 ]
  [ "$(runs web)" -eq 1 ]
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/validate-run.sh" --story "$STORY" --only "gate:Q5 — Unit tests (web)"
  [ "$(runs web)" -eq 2 ]
  [ "$(runs api)" -eq 1 ]
}
