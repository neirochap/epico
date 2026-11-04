#!/usr/bin/env bats
# epico-doctor: read-only health check of .epico/, JSON or one summary line.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  E="$WORK/.epico"
  mkdir -p "$E/stories"
  printf '# Constitution\n\n## Defaults\n\n- x\n\n## Quality\n\n- y\n' > "$E/constitution.md"
  printf 'tracked-md\n' > "$E/.gitpolicy"
  # A healthy tree carries its reuse profile; its absence is tests/reuse-profile-init.bats.
  printf '{"version": 1, "mode": "shadow", "tools": [], "inputs": [], "never": []}\n' > "$E/reuse-profile.json"
  bash "$PLUGIN_ROOT/scripts/claude-md.sh" write --root "$WORK" >/dev/null
}

teardown() {
  rm -rf "$WORK"
}

doctor() { bash "$PLUGIN_ROOT/scripts/doctor.sh" --epico-dir "$E" "$@"; }
story() {  # <dir> <scale> <status> <boxes...>
  mkdir -p "$E/stories/$1"
  { printf -- '---\nstory: %s\nscale: %s\nstatus: %s\n---\n## Task List\n' "$1" "$2" "$3"; shift 3; for b in "$@"; do printf -- '- [%s] 1 - Step\n' "$b"; done; } > "$E/stories/$1/tasks.md"
}
checks() { jq -r '[.findings[].check] | sort | join(",")' <<< "$output"; }
index() { bash "$PLUGIN_ROOT/scripts/epico-index.sh" --epico-dir "$E" >/dev/null; }

@test "a healthy tree: status ok, no findings, and --summary prints nothing" {
  story 001-a fast in-progress x ' '
  index
  run doctor
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok" and .errors == 0 and .warnings == 0'
  run doctor --summary
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no .epico/ at or above the cwd: silent summary, absent status" {
  mkdir -p "$WORK/elsewhere"
  rm -rf "$E"
  cd "$WORK/elsewhere"
  run bash "$PLUGIN_ROOT/scripts/doctor.sh" --summary
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash "$PLUGIN_ROOT/scripts/doctor.sh"
  echo "$output" | jq -e '.status == "absent"'
}

@test "found from a subdirectory of the project" {
  mkdir -p "$WORK/src/deep"
  rm "$E/.gitpolicy"
  cd "$WORK/src/deep"
  run bash "$PLUGIN_ROOT/scripts/doctor.sh"
  echo "$output" | jq -e --arg e "$E" '.epico_dir == $e and any(.findings[]; .check == "gitpolicy")'
}

@test "project files: missing constitution sections are errors; no gitpolicy, no index, no manifest are warnings" {
  printf '# Constitution\n\n## Defaults\n' > "$E/constitution.md"
  bash "$PLUGIN_ROOT/scripts/claude-md.sh" write --root "$WORK" >/dev/null
  rm "$E/.gitpolicy"
  mkdir -p "$E/archive/000-old"
  run doctor
  echo "$output" | jq -e '.status == "error" and .errors == 1'
  [ "$(checks)" = "constitution,gitpolicy,index,manifest" ]
  echo "$output" | jq -e 'any(.findings[]; .check == "constitution" and (.detail | test("Quality")))'
}

@test "an EPICO.md behind the disk is flagged, and the check leaves EPICO.md untouched" {
  story 001-a fast in-progress ' '
  index
  story 002-b fast draft ' '
  before=$(cksum < "$E/EPICO.md")
  run doctor
  [ "$(checks)" = "index" ]
  [ "$(cksum < "$E/EPICO.md")" = "$before" ]
}

@test "stories: no tasks.md is an error unless a planning draft exists; standard without story.md is an error" {
  mkdir -p "$E/stories/001-empty" "$E/stories/002-planning/.draft"
  : > "$E/stories/001-empty/notes.md"
  printf 'phase: 1\n' > "$E/stories/002-planning/.draft/meta.yaml"
  story 003-std standard in-progress ' '
  index
  run doctor
  echo "$output" | jq -e '[.findings[] | select(.severity == "error") | .target] | sort == [".epico/stories/001-empty", ".epico/stories/003-std"]'
}

@test "red-scratch leftovers and dormant drafts are warnings" {
  story 001-a fast in-progress ' '
  mkdir -p "$E/stories/001-a/.draft/red-scratch"
  story 002-dormant fast draft
  find "$E/stories/002-dormant" -exec touch -d '10 days ago' {} +
  story 003-fresh fast draft
  index
  run doctor
  echo "$output" | jq -e '[.findings[] | select(.check == "red-scratch" or .check == "dormant") | .target] | sort == [".epico/stories/001-a", ".epico/stories/002-dormant"]'
  run doctor --stale-days 30
  echo "$output" | jq -e 'all(.findings[]; .check != "dormant")'
}

@test "stall: an in-progress story whose last note is older than the threshold; never without a log" {
  story 001-stuck fast in-progress ' '
  story 002-live fast in-progress ' '
  story 003-nolog fast in-progress ' '
  story 004-done fast done x
  mkdir -p "$E/stories/001-stuck/.draft" "$E/stories/004-done/.draft"
  old=$(date -u -d '-40 minutes' +%Y-%m-%dT%H:%M:%SZ)
  printf '{"story":"001-stuck","task":"2","step":"validation","status":"started","evidence":"","at":"%s"}\n' "$old" > "$E/stories/001-stuck/.draft/progress.log"
  cp "$E/stories/001-stuck/.draft/progress.log" "$E/stories/004-done/.draft/progress.log"
  bash "$PLUGIN_ROOT/scripts/progress-note.sh" --story "$E/stories/002-live" --task 1 --step context --status done
  index
  run doctor
  echo "$output" | jq -e '[.findings[] | select(.check == "stall")] | length == 1 and .[0].target == ".epico/stories/001-stuck" and (.[0].detail | test("task 2, step validation \\(started\\)"))'
  run doctor --stall-minutes 60
  echo "$output" | jq -e 'all(.findings[]; .check != "stall")'
}

@test "an untracked .epico/ copy inside a git worktree is a warning; the main tree is not" {
  git -C "$WORK" init -q
  git -C "$WORK" config user.email test@example.com
  git -C "$WORK" config user.name test
  git -C "$WORK" commit -q --allow-empty -m init
  git -C "$WORK" worktree add -q "$WORK/wt" 2>/dev/null
  mkdir -p "$WORK/wt/.epico/stories"
  story 001-a fast in-progress ' '
  index
  run doctor
  [ "$(checks)" = "worktree-copy" ]
}

@test "summary: one line, the counts and at most three findings" {
  rm "$E/constitution.md" "$E/.gitpolicy" "$WORK/CLAUDE.md"
  for n in 1 2 3; do story "00$n-x" fast in-progress ' '; mkdir -p "$E/stories/00$n-x/.draft/red-scratch"; done
  index
  run doctor --summary
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "epico-doctor: 1 error(s), 4 warning(s) — "*"run epico-doctor for all 5" ]]
}

@test "read-only: the tree is byte-identical after a run" {
  story 001-a standard in-progress ' '
  mkdir -p "$E/stories/001-a/.draft/red-scratch"
  before=$(cd "$WORK" && find . -exec stat -c '%n %s %Y' {} + | sort | cksum)
  run doctor
  run doctor --summary
  after=$(cd "$WORK" && find . -exec stat -c '%n %s %Y' {} + | sort | cksum)
  [ "$before" = "$after" ]
}

@test "CLAUDE.md: a missing or stale Epico block is a warning naming init --repair" {
  story 001-a fast in-progress ' '
  index
  run doctor
  echo "$output" | jq -e 'all(.findings[]; .check != "claude-md")'
  sed -i 's/## Quality/## Quality\n- Lint — `ruff check`/' "$E/constitution.md"
  run doctor
  echo "$output" | jq -e 'any(.findings[]; .check == "claude-md" and (.detail | test("stale.*init --repair")))'
  rm "$WORK/CLAUDE.md"
  run doctor
  echo "$output" | jq -e 'any(.findings[]; .check == "claude-md" and (.detail | test("no Epico block")))'
}
