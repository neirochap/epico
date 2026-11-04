#!/usr/bin/env bats
# Reference files are read with the Read tool, where ${CLAUDE_PLUGIN_ROOT} is
# never substituted, and the Bash tool has no such variable. Claude Code puts
# the plugin's bin/ on PATH, so every script a reference tells Claude to run
# is called through a bin/ wrapper by its bare name.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no reference or agent calls a script through the plugin-root variable or a relative path" {
  # A quoted placeholder (`bash scripts/<name>`) describing the pattern is prose, not a call.
  run bash -c "cd '$ROOT' && git grep -nE 'CLAUDE_PLUGIN_ROOT\}/scripts|bash scripts/[a-z]' -- references agents"
  [ "$status" -eq 1 ]
}

@test "every epico-* command the references name has an executable wrapper" {
  cd "$ROOT"
  names=$(git grep -ohE '\bepico-(archive|claude-md|close|gitpolicy|git-status|index|integration|migrate|next-number|progress|doctor|deviation|inbox|jargon|report|stale|test-diff|supersede|telemetry|validate|validated|check|checkpoint|depdiff|xref)\b' -- references skills | sort -u)
  [ -n "$names" ]
  for n in $names; do
    [ -x "bin/$n" ] || { echo "missing wrapper: bin/$n"; return 1; }
  done
}

@test "each wrapper runs its script: --help reaches the underlying usage" {
  cd "$ROOT"
  for w in bin/*; do
    target=$(grep -E '^exec ' "$w" | grep -oE 'scripts/[a-z-]+\.sh')
    [ -f "$target" ] || { echo "$w points at missing $target"; return 1; }
  done
  run bin/epico-stale --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: monitor-stale.sh"* ]]
}

@test "a link whose text names a .md file points at that file" {
  # A label that names one file while the link opens another tells Claude the
  # rule lives somewhere it may already have read, so it does not follow it.
  cd "$ROOT"
  bad=$(git grep -hoE '\[`?[A-Za-z0-9_.-]+\.md`?\]\([^)#[:space:]]*\.md' -- references agents skills \
    | sed -E 's/^\[`?([^]`]+)`?\]\((.*)$/\1 \2/' \
    | awk '{n=split($2,a,"/"); if ($1 != a[n]) print}')
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}
