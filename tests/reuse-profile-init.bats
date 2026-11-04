#!/usr/bin/env bats
# The reuse profile at init, and its absence in the health summary.
#
#   - references/init-mode.md: init, and init --repair, run
#     `epico-check profile --detect` when the project has no profile, show the
#     proposal, and write .epico/reuse-profile.json in mode shadow.
#   - scripts/doctor.sh --summary: a project with .epico/ and no reuse profile
#     gets a warning naming `/epico:epico init --repair`; a project with one
#     gets nothing; doctor writes nothing either way.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  E="$WORK/.epico"
  mkdir -p "$E/stories/001-a"
  printf '# Constitution\n\n## Defaults\n\n- x\n\n## Quality\n\n- y\n' > "$E/constitution.md"
  printf 'tracked-md\n' > "$E/.gitpolicy"
  printf -- '---\nstory: 001-a\nscale: fast\nstatus: in-progress\n---\n## Task List\n- [ ] 1 - Step\n' > "$E/stories/001-a/tasks.md"
  bash "$PLUGIN_ROOT/scripts/claude-md.sh" write --root "$WORK" >/dev/null
  bash "$PLUGIN_ROOT/scripts/epico-index.sh" --epico-dir "$E" >/dev/null 2>&1
}

teardown() {
  rm -rf "$WORK"
}

doctor() { bash "$PLUGIN_ROOT/scripts/doctor.sh" --epico-dir "$E" "$@"; }

valid_profile() { printf '{"version": 1, "mode": "shadow", "tools": [], "inputs": [], "never": []}\n' > "$E/reuse-profile.json"; }

section() {  # <file> <start-regex> — from the heading to the next ## heading
  awk -v s="$2" '$0 ~ s { on = 1; print; next } on && /^## / { exit } on { print }' "$1"
}

# --- Hostile halves: a lookalike is not a profile ---

@test "a file that only looks like the profile still warns" {
  printf '{}\n' > "$E/reuse-profile.json.bak"
  printf 'version: 1\n' > "$E/reuse-profile.yaml"
  printf '{"version": 1}\n' > "$WORK/reuse-profile.json"
  run doctor --summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"no reuse profile"* ]]
}

@test "with a profile in place the summary is silent again" {
  run doctor --summary
  [[ "$output" == *"no reuse profile"* ]]
  valid_profile
  run doctor --summary
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- The warning ---

@test "no reuse profile: one summary line that warns and names init --repair" {
  run doctor --summary
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"no reuse profile"* ]]
  [[ "$output" == *"/epico:epico init --repair"* ]]
}

@test "no reuse profile: the JSON form carries it as a warning, not an error" {
  run doctor
  [ "$status" -eq 0 ]
  jq -e '.errors == 0 and .warnings >= 1' <<< "$output"
  jq -e '[.findings[] | select(.severity == "warning" and (.detail | test("no reuse profile")))] | length == 1' <<< "$output"
}

@test "doctor never writes the profile it finds missing" {
  run doctor --summary
  [[ "$output" == *"no reuse profile"* ]]
  [ ! -e "$E/reuse-profile.json" ]
}

# --- init-mode.md writes the detected profile ---

@test "init-mode.md: init detects, shows and writes the profile in mode shadow" {
  f="$PLUGIN_ROOT/references/init-mode.md"
  grep -qF 'epico-check profile --detect' "$f"
  grep -qF '.epico/reuse-profile.json' "$f"
  grep -qw 'shadow' "$f"
}

@test "init-mode.md: the Repair section writes the profile when the project has none" {
  repair=$(section "$PLUGIN_ROOT/references/init-mode.md" '^## Repair')
  [ -n "$repair" ]
  [[ "$repair" == *"reuse-profile.json"* || "$repair" == *"profile --detect"* ]]
}
