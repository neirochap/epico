# Shared fixture for the check-reuse suites (tests/check-reuse-*.bats,
# tests/validate-run-*.bats, tests/hook-reuse-guard.bats).
#
# Sourced, never run. Every repository here is a real temp git repository: git
# state is never mocked. A command that must prove it ran — or did NOT run —
# appends one line to a counter file under $OUTSIDE, which lives outside the
# repository, so the act of counting never changes the code fingerprint.

# reuse_setup — a committed repository at $PROJ, the cwd set to it.
reuse_setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CR="$PLUGIN_ROOT/scripts/check-reuse.sh"
  # A run from inside a git hook exports these, and they would point every git
  # call below at a different repository.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  WORK="$(mktemp -d)"
  PROJ="$WORK/proj"
  OUTSIDE="$WORK/outside"
  mkdir -p "$PROJ/src" "$OUTSIDE"
  git -C "$PROJ" init -q
  printf 'echo one\n' > "$PROJ/src/app.sh"
  printf '.env\nbuild/\n' > "$PROJ/.gitignore"
  git -C "$PROJ" add -A
  commit_all "${1:-init}"
  cd "$PROJ" || return 1
}

reuse_teardown() {
  cd / || return 1
  chmod -R u+w "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

commit_all() {  # <message> — commit whatever is staged in $PROJ
  git -C "$PROJ" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m "$1"
}

cr() { bash "$CR" "$@"; }

ledger_dir() {  # [repo] — where git says the shared ledger lives
  printf '%s/epico/reuse' "$(git -C "${1:-$PROJ}" rev-parse --path-format=absolute --git-common-dir)"
}

write_profile() {  # <json> — the project's reuse profile, verbatim
  mkdir -p "$PROJ/.epico"
  printf '%s\n' "$1" > "$PROJ/.epico/reuse-profile.json"
}

profile_mode() {  # <mode> [never-json-array]
  write_profile "$(jq -nc --arg m "$1" --argjson n "${2:-[]}" '{version: 1, mode: $m, tools: [], inputs: [], never: $n}')"
}

bump() {  # <name> — a command string that appends one line to a counter
  printf "echo ran >> '%s/%s'" "$OUTSIDE" "$1"
}

counter() {  # <name> — how many times a bump command ran
  if [ -f "$OUTSIDE/$1" ]; then wc -l < "$OUTSIDE/$1" | tr -d ' '; else echo 0; fi
}

is_hash() {  # <value> — a git object id (sha1 or sha256)
  [[ "$1" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]
}

fp_now() {  # the code fingerprint lookup reports for the cwd
  bash "$CR" lookup -- true 2>/dev/null | jq -r '.fingerprint'
}

key_of() {  # <command> — the reuse key lookup reports for a command
  bash "$CR" lookup -- "$1" 2>/dev/null | jq -r '.key'
}

# vr_story — a story under $PROJ/.epico/stories/007-shelf whose Validation and
# gate commands count their runs under $OUTSIDE. 1.2 fails until
# $OUTSIDE/fixed exists, which makes it pass without touching the code.
vr_story() {
  STORY="$PROJ/.epico/stories/007-shelf"
  mkdir -p "$STORY" "$PROJ/tests"
  touch "$PROJ/tests/shelf_test.sh"
  git -C "$PROJ" add tests/shelf_test.sh
  commit_all "feat(007): shelf core"
  cat > "$STORY/tasks.md" <<'EOF'
---
story: shelf
type: feature
scale: standard
engineering: experiment
requester: layperson
status: in-progress
---

# Implementation Plan - Shelf

## Task List

- [x] 1 - Core
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None_

  - [x] 1.1 - Passing check
    - Tests: Unit · `tests/shelf_test.sh` — one case
    - Validation: `echo ran >> @OUT@/c11` exits 0
    - Commit: "feat(007): shelf core"

  - [x] 1.2 - Failing check
    - Validation: `test -f @OUT@/fixed` exits 0

  - [x] 1.3 - Prose check
    - Validation: the page shows the shelf when opened

  - [~] 1.4 - Live account (deferred: needs the provider's account)
    - Validation: `true`

  - [x] 1.6 - Missing test file
    - Tests: Unit · `tests/absent_test.sh` — one case
    - Validation: `echo ran >> @OUT@/c16`

## Quality Gates

- [ ] All task validations pass
- [ ] Error handling implemented
- [ ] Secrets: `echo ran >> @OUT@/secrets` reports no leaks
EOF
  sed -i "s|@OUT@|$OUTSIDE|g" "$STORY/tasks.md"
}

vr() { bash "$PLUGIN_ROOT/scripts/validate-run.sh" --story "$STORY" "$@"; }

entry() {  # <id> — one entry of validation-run.json, compact
  jq -c --arg i "$1" '.entries[] | select(.id == $i or (.id | startswith($i)))' "$STORY/.draft/validation-run.json" | head -1
}
