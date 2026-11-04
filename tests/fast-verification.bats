#!/usr/bin/env bats
# The deterministic half of verification, done by scripts instead of a sub-agent:
#   scripts/validate-run.sh  runs Validation and gate commands, writes the report
#   bin/epico-close          several boxes in one call
#   scripts/run-report.sh    the run report's skeleton from what is on disk
#   scripts/wait-port.sh     server readiness without sleep loops
# and the rules that send the orchestrator and the Auditor to them.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epico/stories/007-shelf"
  mkdir -p "$STORY" "$PROJ/tests"
  git -C "$PROJ" init -q
  git -C "$PROJ" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m "feat(007): shelf core"
  touch "$PROJ/tests/shelf_test.sh"
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
    - Validation: `true` exits 0
    - Commit: "feat(007): shelf core"

  - [x] 1.2 - Failing check
    - Validation: `false` exits 0

  - [x] 1.3 - Prose check
    - Validation: the page shows the shelf when opened

  - [~] 1.4 - Live account (deferred: needs the provider's account)
    - Validation: `true`

  - [ ] 1.5 - Not done yet
    - Validation: `false`

  - [x] 1.6 - Missing test file
    - Tests: Unit · `tests/absent_test.sh` — one case
    - Validation: `true`

## Quality Gates

- [ ] All task validations pass
- [ ] Error handling implemented
- [ ] Secrets: `true` reports no leaks
- [ ] Data integrity: `tests/shelf_test.sh` proves the write
EOF
}

teardown() { rm -rf "$WORK"; }

result() {  # <id> — the result the run recorded for one entry
  jq -r --arg i "$1" '.entries[] | select(.id == $i or (.id | startswith($i))) | .result' "$STORY/.draft/validation-run.json" | head -1
}

full_run() {  # --only needs a previous run: record one before revalidating
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY"
}

@test "validate-run: runs commands, judges prose, skips [~], ignores [ ]" {
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY"
  [ "$status" -eq 1 ]
  [ "$(jq -r .verdict <<< "$output")" = fail ]
  [ "$(result 1.1)" = PASS ]
  [ "$(result 1.2)" = FAIL ]
  [ "$(result 1.3)" = JUDGE ]
  [ "$(result 1.4)" = SKIP ]
  [ -z "$(result 1.5)" ]
  [ "$(result 1.6)" = FAIL ]
  [ "$(result 'Secrets')" = PASS ]
  [ "$(result 'Data integrity')" = JUDGE ]
  [ "$(result 'Error handling')" = JUDGE ]
  [ "$(result 'All task validations pass')" = FAIL ]
}

@test "validate-run: writes the validation-report schema the Auditor reads" {
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY"
  y="$STORY/.draft/validation-report.yaml"
  grep -q '^verdict: fail$' "$y"
  grep -q '^results:$' "$y"
  grep -q '^  - task: "1.4"$' "$y"
  grep -q '^    qualifier: "deferred"$' "$y"
  grep -q '^gates:$' "$y"
  run bash "$ROOT/scripts/report.sh" --story "$STORY"
  [ "$(jq -r .validation.verdict <<< "$output")" = fail ]
}

@test "validate-run: a commit the log lacks fails the sub-task that names it" {
  sed -i 's/feat(007): shelf core"/feat(007): never committed"/' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY"
  [ "$(result 1.1)" = FAIL ]
  jq -e '.entries[] | select(.id == "1.1") | .detail | test("commit not found")' "$STORY/.draft/validation-run.json"
}

@test "validate-run --only re-runs the named entries, and an unselected PASS whose code changed" {
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY"
  sed -i 's/`false` exits 0/`true` exits 0/' "$STORY/tasks.md"
  # A new untracked file is a code change: 1.1 passed on other code, so it runs
  # again and is settled on the new fingerprint. Keeping an unselected PASS on
  # unchanged code is tests/validate-run-only-fingerprint.bats.
  touch "$PROJ/tests/absent_test.sh"
  before=$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$STORY/.draft/validation-run.json")
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.2,1.6
  [ "$(result 1.2)" = PASS ]
  [ "$(result 1.6)" = PASS ]
  [ "$(result 1.1)" = PASS ]
  [ "$(jq -r '.entries[] | select(.id == "1.1") | .fingerprint' "$STORY/.draft/validation-run.json")" != "$before" ]
  [ "$(jq -r .verdict <<< "$output")" = pending ]
}

@test "validate-run: a hanging command fails at its timeout" {
  full_run
  sed -i 's/`true` exits 0/`sleep 5` exits 0/' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.1 --timeout 1
  [ "$(result 1.1)" = FAIL ]
  jq -e '.entries[] | select(.id == "1.1") | .detail | test("timed out")' "$STORY/.draft/validation-run.json"
}

@test "validate-run: refuses without a story holding tasks.md" {
  run bash "$ROOT/scripts/validate-run.sh" --story "$WORK/nowhere"
  [ "$status" -eq 2 ]
}

@test "run-report: skeleton carries the recorded line, the boxes and the commits" {
  run bash "$ROOT/scripts/run-report.sh" --story "$STORY"
  [ "$status" -eq 0 ]
  r="$STORY/.draft/run-report.md"
  grep -q '^standard · layperson · experiment · 6 boxes — 4 closed, 1 deferred, 1 open$' "$r" || { cat "$r"; false; }
  grep -q '^- \[x\] 1.1 - Passing check$' "$r"
  grep -q 'feat(007): shelf core' "$r"
  run bash "$ROOT/scripts/run-report.sh" --story "$STORY"
  [ "$(jq -r .written <<< "$output")" = false ]
}

@test "wait-port: open port answers, closed port times out" {
  python3 -m http.server 38771 --bind 127.0.0.1 >/dev/null 2>&1 &
  pid=$!
  run bash "$ROOT/scripts/wait-port.sh" 38771 --timeout 5
  kill "$pid"
  [ "$status" -eq 0 ]
  [ "$(jq -r .open <<< "$output")" = true ]
  run bash "$ROOT/scripts/wait-port.sh" 38772 --timeout 1
  [ "$status" -eq 1 ]
  run bash "$ROOT/scripts/wait-port.sh" notaport
  [ "$status" -eq 2 ]
}

@test "epico-close: several boxes in one call, stopping at the first refusal" {
  run bash "$ROOT/bin/epico-close" "$STORY" 1.5 1.5
  [ "$status" -eq 1 ]
  [ "$(grep -c '^\s*- \[x\] 1.5' "$STORY/tasks.md")" -eq 1 ]
  [ "$(grep -c '^{' <<< "$output")" -eq 2 ]  # the close, then the refusal — and nothing after it
}

@test "rules: the orchestrator runs the script, the Auditor settles only JUDGE, one fix round" {
  v="$ROOT/references/validate-mode.md"
  grep -q 'then run \*\*`epico-validate-run --story <dir>`\*\*' "$v"
  grep -q "\*\*On its \`verdict: fail\`, spawn nothing\*\*" "$v"
  grep -q '\*\*Settle only the entries whose result is `JUDGE`\*\*' "$v"
  grep -q '\*\*The revalidation re-checks the failures, never the whole story.\*\*' "$v"
  grep -q '\*\*bounded to one fix round\*\*' "$v"
  grep -q '\*\*Settle only the `JUDGE` entries\*\*' "$ROOT/agents/auditor.md"
}

@test "rules: verifiers take reviewModel; servers are waited for; boxes close in one call" {
  jq -e '.userConfig.reviewModel.default == "inherit"' "$ROOT/.claude-plugin/plugin.json"
  grep -qF 'reviewModel`: `${user_config.reviewModel}` [`inherit`]' "$ROOT/skills/epico/SKILL.md"
  grep -q 'take the \*\*`reviewModel`\*\* option' "$ROOT/references/run-mode.md"
  grep -q '`reviewModel` option' "$ROOT/references/run-tech-review.md"
  grep -q 'waited for with `epico-wait-port <port>`' "$ROOT/references/run-mode.md"
  grep -qF 'epico-wait-port <port> --pid $!' "$ROOT/references/run-mode.md"
  grep -q '`epico-close <story> 2.1 2.2 2.3`' "$ROOT/references/run-mode.md"
  grep -q '`epico-run-report --story <dir>` writes the skeleton' "$ROOT/references/run-mode.md"
}

@test "wait-port --pid: a server that exits ends the wait at once" {
  bash -c 'exit 3' &
  pid=$!
  wait "$pid" || true
  SECONDS=0
  run bash "$ROOT/scripts/wait-port.sh" 38773 --timeout 20 --pid "$pid"
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 5 ]
  [ "$(jq -r .exited <<< "$output")" = true ]
}

@test "validate-run: a command that backgrounds a server returns, and the server is killed" {
  full_run
  sed -i 's/`true` exits 0/`sleep 30 \& echo $! > server.pid` exits 0/' "$STORY/tasks.md"
  SECONDS=0
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.1 --timeout 20
  [ "$SECONDS" -lt 10 ]
  [ "$(result 1.1)" = PASS ]
  [ -s "$PROJ/server.pid" ]
  # Gone, or a zombie: a container whose PID 1 never reaps keeps the killed
  # process in the table, and `kill -0` still answers for it.
  state=$(awk '{print $3}' "/proc/$(cat "$PROJ/server.pid")/stat" 2>/dev/null || true)
  [ -z "$state" ] || [ "$state" = Z ]
}

@test "validate-run: a Validation with two commands runs the first and leaves the rest to JUDGE" {
  full_run
  sed -i 's/`true` exits 0/`true` and, with the server running, `curl -fsS localhost:1` returns the page/' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.1
  [ "$(result 1.1)" = JUDGE ]
  jq -e '.entries[] | select(.id == "1.1") | .detail | test("`true` exit 0") and test("curl")' "$STORY/.draft/validation-run.json"
  sed -i 's/`false` exits 0/`false` and then `true`/' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.2
  [ "$(result 1.2)" = FAIL ]
}

@test "validate-run: cargo's per-binary summaries are added up, not cut to the doc-test line" {
  full_run
  cat > "$PROJ/fake-cargo.sh" <<'SH'
#!/usr/bin/env bash
printf 'running 30 tests\ntest result: ok. 30 passed; 0 failed; 0 ignored\n\nrunning 3 tests\ntest result: ok. 3 passed; 0 failed; 0 ignored\n\n   Doc-tests app\nrunning 0 tests\ntest result: ok. 0 passed; 0 failed; 0 ignored\n'
SH
  chmod +x "$PROJ/fake-cargo.sh"
  sed -i 's|`true` exits 0|`./fake-cargo.sh` exits 0|' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.1
  jq -e '.entries[] | select(.id == "1.1") | .detail | test("33 passed, 0 failed")' "$STORY/.draft/validation-run.json"
}

@test "validate-run: a command holding a <placeholder> is JUDGE, never run" {
  full_run
  sed -i 's/`true` exits 0/`touch ran-it \&\& false -j <job>` for each job/' "$STORY/tasks.md"
  sed -i 's/^- \[ \] Secrets: `true` reports no leaks/- [x] CI mirror: `act -j <job>` for each job/' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.1,gate:CI
  [ "$(result 1.1)" = JUDGE ]
  [ "$(result 'CI mirror')" = JUDGE ]
  [ ! -e "$PROJ/ran-it" ]
}

@test "validate-run: shell redirection is not a placeholder" {
  full_run
  sed -i 's/`true` exits 0/`true <\/dev\/null >\/dev\/null` exits 0/' "$STORY/tasks.md"
  run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" --only 1.1
  [ "$(result 1.1)" = PASS ]
}

@test "rules: a generated gate's first backtick span is the whole command, with no placeholder" {
  grep -qF 'The first backtick span of a gate is the whole command validate runs' "$ROOT/references/quality-catalog.md"
  grep -qF 'no `<placeholder>`' "$ROOT/references/quality-catalog.md"
}
