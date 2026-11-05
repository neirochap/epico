---
story: 030-validation-result-reuse
type: feature
scale: full
scale_reason: a new contract (ledger, profile and epico-check JSON) read by scripts, hooks and agents, plus a cross-cutting change with no established pattern — every check-running caller is re-routed
engineering: project
requester: developer
run-model: sonnet
version: 4
created: 2026-11-04
last-refined: 2026-11-05
history:
  - v1: Initial story
  - v2: Refine after the run - R2.15, R2.16 and R4.8 added; the design describes the fingerprint, key, ledger lock and run as built; Task 10 adds regression guards for the review findings
  - v3: Refine after validation fixes round 1 - R4.8 reworded, R4.9 to R4.12 added; the design's Ledger describes the owner token and void markers; Task 12 hardens the ledger lock
  - v4: Refine after the second validation - uutils mkdir is not atomic, so the owner file, created with O_EXCL, decides who holds the ledger lock; Task 13
status: in-progress
---

# Implementation Plan - Validation Result Reuse

## Overview

The plan builds outwards:
1. The `--only` fix, which stands alone.
2. The check runner (`scripts/check-reuse.sh` + `bin/epico-check`): fingerprint, key, run, ledger, then shadow.
3. Re-routing of `validate-run.sh` through the runner, and the guard that keeps agents out of the ledger.
4. Per-project profile detection, wired into init and doctor.
5. The reference that routes the agents' check runs, and the gate guidance.
6. The contract checks, the README and the whole local check from a clean clone.
7. Regression guards (added by the refinement after the run): the defects the technical review found were fixed and verified by hand; Task 10 gives each a permanent test.

Every Unit and Integration test is pre-authored under `.draft/authored-tests/` and confirmed Red. Nothing shipped names a real project.

## Task List

- [x] 1 - Refuse --only revalidation with no previous run
  - _Complexity: Simple | Tests: Integration | Risks: six existing cases rely on the old behaviour | Dependencies: None_
  - Objective: a revalidation of named entries can no longer pass on a fraction of the story's checks

  - [x] 1.1 - Refuse --only when no validation-run.json exists
    - Context:
      - Files: `scripts/validate-run.sh` (`--only` merge at the `PREV='[]'` line), `tests/fast-verification.bats` (setup and the `--only` cases)
    - Objective: `--only` with no previous run exits 2 without writing a report
    - ToDo:
      - **Refusal:** in `scripts/validate-run.sh`, before the `PREV='[]'` / `--only` merge, when `--only` is set and `$JSON` does not exist:
        - print `validate-run.sh: --only needs a previous full run; run without --only first` to stderr and exit 2;
        - no JSON on stdout, no YAML written, and a leftover `validation-report.yaml` stays byte-identical.
      - **Existing cases:** update the six `tests/fast-verification.bats` cases that call `--only` with no prior run (`:122 :198 :210 :225 :232 :240`) so they run a full validation first.
      - **Test:** copy the authored test from `.draft/authored-tests/tests/validate-run-only-refusal.bats`.
    - Tests: Integration · `tests/validate-run-only-refusal.bats` — --only with no prior run exits 2 with no JSON, no report and no command run; message names a full run; leftover YAML with no run JSON still refused and left byte-identical; after a full run --only proceeds
    - Validation: `bats tests/validate-run-only-refusal.bats tests/fast-verification.bats`
    - Requirements: R1.1
    - Quality: Q1, Q2, Q3
    - Commit: "fix(030): refuse --only revalidation with no previous run"

- [x] 2 - Code fingerprint and reuse key
  - _Complexity: High | Tests: Unit | Risks: every `.epico` state, worktrees, submodules | Dependencies: None_
  - Objective: one deterministic key per check that changes exactly when the command, the code or the environment changes

  - [x] 2.1 - check-reuse.sh skeleton, bin/epico-check and the fingerprint
    - Context:
      - Files: `bin/epico-validate-run` (wrapper pattern), `scripts/close-subtask.sh` (usage errors print no JSON, header lines 9-37), `tests/bin-wrappers.bats` (the hand-kept list near line 19), the design's "Reuse key" and "Implementation Gotchas"
    - Objective: `epico-check lookup -- <cmd>` reports the code fingerprint, or null with the reason none could be computed
    - ToDo:
      - **Script and wrapper:**
        - Create `scripts/check-reuse.sh`. Its header documents the JSON contract and exit 0/1/2; it runs under `set -euo pipefail`. A usage error goes to stderr with exit 2 and **no JSON**.
        - Create `bin/epico-check` as the 4-line wrapper.
        - Add `check` to the list in `tests/bin-wrappers.bats`.
      - **`fingerprint()`:**
        1. `idx=$(mktemp)`, removed by a trap.
        2. Copy `git rev-parse --git-path index`, resolved against the toplevel when relative. The copy keeps git's stat cache; an empty temp index re-hashes the whole tree.
        3. `GIT_INDEX_FILE=$idx git add -A -- .`
        4. `GIT_INDEX_FILE=$idx git rm -r -q --cached --ignore-unmatch -- .epico .epic`
        5. `GIT_INDEX_FILE=$idx git write-tree`
      - **Two forms to avoid:**
        - Never use an `:(exclude).epico` pathspec: it exits 1 when `.epico/` is gitignored.
        - Never branch on `git check-ignore`: it reports an ignored directory that holds a tracked file as not ignored.
      - **Null fingerprint, with a `reason`, when:**
        - the directory is not a work tree;
        - any git step fails (an unreadable file makes `add` fail) — call each step and handle its error;
        - `git status --porcelain --ignore-submodules=none` shows a submodule with modified content.
      - **`lookup -- <cmd>`** emits `mode`, `would_reuse`, `fingerprint`, `key`, `last` and `reason`. `key` stays null until 2.2.
    - Tests: Unit · `tests/check-reuse-fingerprint.bats` — tracked edit, new untracked file and `.epico-notes.md`/`.epic.md` change it; `.epico` versioned, gitignored, gitignored-with-a-tracked-file keep it; an ignored non-input file keeps it; clean checkout equals `HEAD^{tree}`; real index untouched; lookup JSON keys; null + reason for a non-git dir, an unreadable file, a dirty submodule (a clean submodule still fingerprints); usage exit 2 with no JSON; wrapper. The `key` assertion of the lookup contract case needs the key built in 2.2, so that one case passes once 2.2 is done
    - Validation: `bats tests/check-reuse-fingerprint.bats tests/bin-wrappers.bats`
    - Requirements: R2.3, R2.7, R2.11
    - Quality: Q1, Q2, Q3

  - [x] 2.2 - Profile loading and the reuse key
    - Context:
      - Files: the design's "reuse-profile.json" and "Reuse key"
    - Objective: the key changes when an input file, a probe's output or the profile changes, and the profile is never modified
    - ToDo:
      - **Load the profile:** read `.epico/reuse-profile.json` from the toplevel with jq.
        - Absent: defaults `{"version":1,"mode":"shadow","tools":[],"inputs":[],"never":[]}`, `reason: "profile absent"`.
        - Invalid JSON, or `version` ≠ 1: the same defaults plus a stderr warning. Never write the file.
      - **Build the key:** `git hash-object --stdin` over `jq -cS` of `{command, tree, tools, inputs, profile}`:
        - **`tools`:** each probe's output from `timeout "${EPICO_REUSE_PROBE_TIMEOUT:-10}" bash -c "$probe" 2>&1`, or `absent` when `command -v` of its first word fails. Run each probe once per invocation.
          - The output is captured even on a non-zero exit (`java -version` writes to stderr): use `|| status=$?` and never let `set -e` abort.
          - Exit 124 means no key, with `reason: "probe timed out: <probe>"`.
        - **`inputs`:** each blob from `git hash-object --no-filters -- <path>` (no `-w`, so no object is written; portable where `sha256sum` is not), or `absent` when the path does not exist.
          - A path that exists but is a directory or unreadable means no key, with a reason naming it. Call `hash-object` and handle its error.
        - **`profile`:** the profile file's blob hash, or `absent`.
        - With no key, the command still runs (3.1).
    - Tests: Unit · `tests/check-reuse-key.bats` — key changes for a gitignored listed input (fingerprint unchanged), swapped input contents, an input appearing, probe output, profile edit, a different command; a probe exiting non-zero keys on its output; a probe hanging past EPICO_REUSE_PROBE_TIMEOUT=1, a directory input and an unreadable input each give key null, a reason, and the command still runs; stable for an absent probe binary, an unlisted ignored file, no change; absent profile gives shadow and "profile absent", lookup keeps `last`; invalid JSON and v2-saying-on give shadow plus a warning, file untouched; an invalid profile still runs. The hang, directory, unreadable-input and invalid-profile cases call `check-reuse.sh run`, delivered in 3.1: they pass, and this box closes, once 3.1 is done
    - Validation: `bats tests/check-reuse-key.bats`
    - Requirements: R2.4, R2.5, R2.6, R2.11, R2.13, R4.4
    - Quality: Q1, Q2, Q3, Q11

  - Commit: "feat(030): fingerprint and reuse key for epico-check"

- [x] 3 - Run, ledger and shadow
  - _Complexity: High | Tests: Unit + Integration | Risks: moving validate-run's run semantics intact; concurrent writers | Dependencies: Task 2_
  - Objective: a check is run or reused by one script that alone records results

  - [x] 3.1 - The run subcommand
    - Context:
      - Files: `scripts/validate-run.sh` (`run_cmd`, under the comment "Output goes to a file, not a pipe", and `runner_totals`)
    - Objective: `epico-check run [--timeout <s>] -- <cmd>` returns the verdict a direct run would
    - ToDo:
      - **Move the run semantics:** move `run_cmd` and `runner_totals` into `check-reuse.sh` with unchanged behaviour:
        - output to a file, never a pipe — a backgrounded `cargo run &` once held a pipe open until the timeout;
        - `setsid --fork --wait` and `timeout`;
        - process-group kill after return;
        - cargo totals summed.
      - **Map the exit code:** 0 → PASS; any other → FAIL; 124 → FAIL with evidence `timed out after <s>s`.
      - **Fingerprint:** compute it before deciding, and report it whenever it can be computed — in every mode, never-list commands included. With no fingerprint or no key, the command still runs and `reason` says why.
      - **Measure and report:**
        - measure `secs` with bash `SECONDS` (`date +%s%N` is unsupported on macOS);
        - emit `mode`, `decision`, `would_reuse`, `result`, `exit`, `evidence`, `secs`, `fingerprint`, `key` and `reason`;
        - exit 0 on PASS, 1 on FAIL;
        - `--timeout` defaults to 300.
    - Tests: Unit · `tests/check-reuse-run.bats` — FAIL is exit 1 with the command's own code; printing PASS while failing is FAIL; timeout evidence `timed out after 1s`; last-line evidence; one JSON line on stdout; contract keys and types; a backgrounded server is killed; cargo totals summed; a non-git dir still runs; usage exit 2 runs nothing
    - Validation: `bats tests/check-reuse-run.bats`
    - Requirements: R2.11, R2.12, R2.14
    - Quality: Q1, Q2, Q3

  - [x] 3.2 - The ledger and the decision table
    - Context:
      - Files: the design's "Decision table (`run`)", "Ledger and shadow log" and "Error Handling Strategy"
    - Objective: on `on`, a PASS for an identical key is returned without running; every other row of the table runs
    - ToDo:
      - **Location:** `$(git rev-parse --path-format=absolute --git-common-dir)/epico/reuse`, created on first write. Plain `--git-common-dir` is relative in the main worktree, so always use the absolute form.
      - **Reading:** read `ledger.json` with jq. On invalid JSON, a wrong shape or `version` ≠ 1:
        - `mv` it to `ledger.json.unreadable-$(date -u +%Y%m%dT%H%M%SZ)`, adding `-N` when that name exists, so an earlier copy is never replaced;
        - start from an empty ledger.
        - Call the `mkdir` and the set-aside `mv` with their errors handled. On failure (a read-only directory), warn and run as if nothing were recorded; never let `set -e` abort before the command runs.
      - **The decision table:**
        - **Runs and writes nothing:** `off`; no fingerprint or no key; a command containing a `never` entry (literal substring). The `fingerprint` is still reported in these rows (3.1).
        - **Reused, not run:** `on` with a PASS hit and no `--fresh`.
        - **Every other row:** run and write.
        - **Only a PASS is ever a hit.**
      - **Writing:** jq to a temp file in the same directory, then `mv` (atomic, no flock; a lost update costs one re-run).
        - Cap at 2000 entries, dropping the oldest `at`.
        - Call the write and handle its error: on failure, warn on stderr and keep the command's verdict and exit code.
    - Tests: Integration · `tests/check-reuse-ledger.bats` — FAIL never reused; never-list runs and records nothing; never entry is a literal substring; code change re-runs; --fresh replaces and a recorded FAIL outlives the old PASS; mode off records nothing; a clone does not share the ledger; mode off and never-list still report the fingerprint; a hit is reused without running; entry shape; a linked worktree reuses main's PASS; a v2 ledger holding a PASS for this key is not trusted; two corrupt ledgers give two set-aside copies; wrong shape; first write; a read-only ledger keeps verdict and exit and warns; an unreadable ledger in a read-only dir still runs, keeps verdict and exit, warns, is not overwritten; cap 2000 drops the oldest `at`; no temp files left
    - Validation: `bats tests/check-reuse-ledger.bats`
    - Requirements: R2.1, R2.2, R2.8, R2.9, R2.10, R2.11, R3.3, R3.4, R4.3, R4.5, R4.7
    - Quality: Q1, Q2, Q3, Q8, Q11

  - [x] 3.3 - Shadow log and stats
    - Context:
      - Files: the design's "Ledger and shadow log"
    - Objective: shadow mode runs everything and records what would have been reused; `stats` summarises it
    - ToDo:
      - **Shadow log:** in `shadow`, after a run, append one line `{at,command,key,would_reuse,result,secs}` to `shadow.log`.
        - `would_reuse` = a ledger PASS hit for the key **before** the run.
        - Trim to 5000 lines, oldest first, through a temp file and `mv`.
        - Call the append, the trim and the `mv` with their errors handled. On failure, warn on stderr and keep the command's verdict and exit code.
      - **`stats`:** jq over the log → `{runs, would_reuse, agreed, disagreed:[{command,at}], secs_reusable}`.
        - `disagreed` = would-reuse with a FAIL result.
        - A missing or empty log gives zeros.
    - Tests: Unit · `tests/check-reuse-shadow.bats` — a recorded FAIL never makes would_reuse; on and off write no shadow line; default with no profile runs twice with would_reuse on the second; explicit shadow; six-field lines; stats runs, would_reuse, agreed, secs_reusable and disagreed (a flaky check counts, a fresh FAIL does not); empty stats; cap 5000; a read-only shadow.log and directory keep the PASS/FAIL verdict and exit code, warn, and add no line
    - Validation: `bats tests/check-reuse-shadow.bats`
    - Requirements: R3.1, R3.2, R3.4, R4.7
    - Quality: Q1, Q2, Q3, Q8

  - Commit: "feat(030): epico-check run, ledger and shadow stats"

- [x] 4 - validate-run settles entries through epico-check
  - _Complexity: Moderate | Tests: Integration | Risks: report readers; the existing --only case | Dependencies: Task 1, Task 3_
  - Objective: Validate runs, reuses and keeps entries by the same key the agents use

  - [x] 4.1 - Run each entry through check-reuse.sh
    - Context:
      - Files: `scripts/validate-run.sh` (`check()`, and the JSON/YAML writers at the end), `scripts/run-report.sh`, `scripts/report.sh`, `tests/checkbox-grammar.bats`
    - Objective: every entry carries `reused` and `fingerprint`, and every existing field and reader is unchanged
    - ToDo:
      - **Run through the runner:** in `check()`, replace `run_cmd` with `bash "$(dirname "${BASH_SOURCE[0]}")/check-reuse.sh" run --timeout "$TIMEOUT" ${FRESH:+--fresh} -- "$val"` (script-to-script by path).
      - **Parse its line** with jq. A missing or invalid JSON line is a FAIL carrying its stderr as the detail; handle that error.
      - **Report fields:**
        - add `reused` and `fingerprint` to each entry, keeping `kind`, `id`, `result`, `qualifier` and `detail`;
        - add `reused:` to the YAML;
        - add a `--fresh` flag.
      - **Readers:** `run-report.sh`, `report.sh` and `checkbox-grammar.bats` keep passing.
    - Tests: Integration · `tests/validate-run-reuse.bats` — a reused PASS still fails on a missing test file; a FAIL is never reused; --fresh passes through; an unchanged PASS is reused without running; shadow never reuses; reused and fingerprint on every entry; reader fields unchanged; YAML gains reused:; --timeout passes through
    - Validation: `bats tests/validate-run-reuse.bats tests/checkbox-grammar.bats tests/fast-verification.bats`
    - Requirements: R1.5
    - Quality: Q1, Q2, Q3

  - [x] 4.2 - Keep an unselected PASS only on the same code
    - Context:
      - Files: `scripts/validate-run.sh` (the `--only` merge), `tests/fast-verification.bats` (the `--only` case)
    - Objective: `--only` re-runs a previous PASS whose code changed, or that carries no fingerprint
    - ToDo:
      - **The merge:** keep an unselected previous PASS only when its `fingerprint` equals the current fingerprint from `check-reuse.sh lookup`. Otherwise run it through `check()`.
        - A missing or null `fingerprint` (a pre-030 report) means run.
        - An unusable `lookup` (non-zero exit, no JSON or invalid JSON) counts as an unknown fingerprint and means run. Call `lookup` and handle its error.
        - Keep calling `check-reuse.sh` from `validate-run.sh`'s own directory, and take the current fingerprint from `lookup` only. The authored test swaps in a `check-reuse.sh` that breaks `lookup`.
        - SKIP and JUDGE entries are kept.
      - **Existing case:** update the `fast-verification.bats` case whose `touch tests/absent_test.sh` now counts as a code change. It asserts the re-run instead of byte-equality.
    - Tests: Integration · `tests/validate-run-only-fingerprint.bats` — a tracked edit re-runs unselected PASS entries (SKIP and JUDGE kept); a new untracked file re-runs; no fingerprint and a null fingerprint re-run; an unusable lookup (exit 1 with no output, invalid JSON, empty output) re-runs; same code keeps the entry byte-identical without running; editing only `.epico/` keeps it; mode off and a never-list command keep an identical-code PASS with its fingerprint
    - Validation: `bats tests/validate-run-only-fingerprint.bats tests/fast-verification.bats`
    - Requirements: R1.2, R1.3, R1.4
    - Quality: Q1, Q2, Q3

  - Commit: "feat(030): validate-run settles entries through epico-check"

- [x] 5 - Ledger write guard
  - _Complexity: Moderate | Tests: Integration | Risks: path spellings; blocking a session | Dependencies: Task 3_
  - Objective: an agent cannot write a PASS into the ledger by hand

  - [x] 5.1 - hook-reuse-guard.sh
    - Context:
      - Files: `scripts/hook-executor-guard.sh` and `scripts/hook-archive-guard.sh` (deny JSON shape), `hooks/hooks.json`, `tests/hook-contracts.bats` (`onFailure` rule)
    - Objective: Edit/Write and writing shell commands into the ledger directory are denied; everything else passes
    - ToDo:
      - **Create `scripts/hook-reuse-guard.sh`.** It reads the PreToolUse JSON from stdin with jq and resolves the ledger directory exactly as `check-reuse.sh` does: `git -C "$cwd" rev-parse --path-format=absolute --git-common-dir` + `/epico/reuse`.
      - **Edit|Write:** canonicalise `tool_input.file_path` — relative against cwd, `..` collapsed, the symlinks of its existing parent resolved. Deny when it is inside that directory, with a message naming that the ledger is written only by `epico-check run`.
      - **Bash:** deny a command that names that directory together with `>`, `>>`, `cp`, `mv`, `tee` or `rm`, **whatever else it runs**. No exemption for a command that also calls `epico-check`, since the runner writes the ledger itself. `cp forged.json <dir>/ledger.json && epico-check stats` must be denied. A command that only runs `epico-check` stays allowed.
      - **Fail open inside the script:** any own error (bad stdin, no git) exits 0. `tests/hook-contracts.bats` requires `onFailure: "block"` in `hooks.json`, so the script itself is what keeps a session unblocked.
      - **Register** in `hooks/hooks.json` PreToolUse beside `hook-executor-guard.sh`, for `Edit|Write` and `Bash`.
    - Tests: Integration · `tests/hook-reuse-guard.bats` — near-miss paths and read-only Bash allowed; Edit and Write denied with a message naming `epico-check run`; relative, `..` and symlink spellings denied; a not-yet-existing directory denied; a linked worktree targeting main's ledger denied; redirect / cp / mv / tee / rm denied; no exemption: `cp … && epico-check stats`, `epico-check stats > <ledger>/x`, `epico-check run -- true; cp …` and `check-reuse.sh stats | tee …` denied while `epico-check run -- make test` alone is allowed; fail-open on bad input; Read allowed; hooks.json registration
    - Validation: `bats tests/hook-reuse-guard.bats tests/hook-contracts.bats`
    - Requirements: R4.1, R4.2, R4.6
    - Quality: Q1, Q2, Q3, Q12
    - Commit: "feat(030): guard the reuse ledger against agent writes"

- [x] 6 - Per-project reuse profile
  - _Complexity: Moderate | Tests: Unit + Integration | Risks: false inputs from ignored files | Dependencies: Task 2_
  - Objective: every project gets a reuse key fitted to its own toolchain and local files

  - [x] 6.1 - profile --detect
    - Context:
      - Files: the design's "reuse-profile.json" (the detect bullets)
    - Objective: a proposed profile is printed from the manifests and ignored files actually present, and nothing is written
    - ToDo:
      - **Tool probes:** from the toplevel, map each manifest to its probe, only when the binary is on PATH (`command -v`). One probe per toolchain, even with two manifests.
        - `package.json` → `node --version`, plus `<packageManager tool> --version` (the name before `@`, via jq; skipped when absent);
        - `go.mod` → `go version`;
        - `Cargo.toml` → `rustc --version`;
        - `pyproject.toml` or `requirements*.txt` → `python3 --version`;
        - `composer.json` → `php --version`;
        - `build.gradle*`/`pom.xml` → `java -version`;
        - `Gemfile` → `ruby --version`;
        - `deno.json*` → `deno --version`.
      - **Inputs:** `git ls-files --others --ignored --exclude-standard`, filtered to basenames `.env`, `.env.*`, `.dev.vars` and `*.local.{json,yaml,yml,toml,php}`. Paths under `node_modules/` or `vendor/` are excluded, and so are `.envrc` and `*.local.md`.
      - **Unreadable input:** a malformed `package.json` skips its `packageManager` probe (the `node` probe stays). Outside a git work tree, `inputs` is `[]`. Each case warns on stderr and still prints a profile with exit 0; call `jq` and `git ls-files` with their errors handled.
      - **`never: []`.** Print the JSON; write nothing.
    - Tests: Unit · `tests/check-reuse-profile.bats` — a manifest without its binary gives no probe; a binary without its manifest gives none; two manifests of one toolchain give one probe; an absent packageManager tool is skipped; all nine probes; inputs patterns (excluding a tracked file, `.envrc`, `*.local.md`, `node_modules/`, `vendor/`); never is []; a malformed package.json keeps node, skips its packageManager probe, exits 0 with a warning; detect outside git keeps the probes, gives inputs [], exits 0 with a warning; --detect writes nothing
    - Validation: `bats tests/check-reuse-profile.bats`
    - Requirements: R5.1, R5.2, R5.5
    - Quality: Q1, Q2, Q3

  - [x] 6.2 - init writes the profile, doctor warns without one
    - Context:
      - Files: `references/init-mode.md` (init and Repair sections), `scripts/doctor.sh` (`--summary`), `tests/doctor.bats` (lines 26 and 130)
    - Objective: init produces the profile in shadow mode; the health summary names the command when it is missing
    - ToDo:
      - **`init-mode.md`:** on init and `init --repair`, when `.epico/reuse-profile.json` is absent:
        - run `epico-check profile --detect`;
        - show the proposal in one line;
        - ask once for never-reuse commands — checks needing credentials, docker, a database or a live service;
        - write the file with `mode: shadow`.
      - **`doctor.sh --summary`:** warn (a warning, not an error) `no reuse profile — run /epico:epico init --repair` when `.epico/` exists without the profile. It writes nothing.
      - **Existing cases:** update `tests/doctor.bats:26` and `:130`, whose healthy-tree summary and warning count change.
    - Tests: Integration · `tests/reuse-profile-init.bats` — lookalike profile files still warn; a real profile silences the summary; one summary line naming `/epico:epico init --repair`; a warning, not an error, in JSON; doctor writes nothing; init-mode.md init and Repair sections
    - Validation: `bats tests/reuse-profile-init.bats tests/doctor.bats`
    - Requirements: R5.3, R5.4
    - Quality: Q1, Q2, Q3

  - Commit: "feat(030): detect and write the per-project reuse profile"

- [x] 7 - Route check runs through epico-check
  - _Complexity: Moderate | Tests: Unit | Risks: run-mode.md line budget | Dependencies: Task 3_
  - Objective: every repeatable check run goes through reuse, and no must-fail or clean-copy run does

  - [x] 7.1 - check-reuse.md and the pointers
    - Context:
      - Files: `agents/executor.md` (step 4 "Run the Validation command" and the Refactor re-run), `agents/auditor.md` (Part 2 and the bugfix base-commit guard), `references/run-mode.md` (inline route, end-of-run gates, Deferred E2E), `references/lean-route.md` (the whole check), `references/validate-mode.md`, `agents/test-advisor.md`, `agents/final-reviewer.md`, `tests/file-size.bats`
    - Objective: `references/check-reuse.md` is the single home of the routing rules, and each routed step points to it
    - ToDo:
      - **Write `references/check-reuse.md`:**
        - the routed callers;
        - the runs that never route, with the reason (they must observe a FAIL, or run outside the working tree);
        - the modes, and how to switch (`mode` in the profile);
        - how to read `epico-check stats` — a disagreement is not a false green: it is a flaky check, or an external-state one to add to `never`;
        - keep secrets out of gate commands, since the ledger stores command strings under the git dir.
      - **One pointer line** ("run it with `epico-check run -- <cmd>`") in:
        - `executor.md` steps 4–5;
        - `auditor.md` Part 2;
        - `run-mode.md` inline route and end-of-run gates — the file stays ≤ 500 lines (489 today);
        - `lean-route.md`;
        - `validate-mode.md`.
      - **Leave untouched:** the Test Advisor's Red runs, the Deferred E2E Red, the Auditor's bugfix base-commit guard and the final reviewer's clean copy.
    - Tests: Unit · `tests/check-reuse-routing.bats` — test-advisor.md, final-reviewer.md and the Deferred E2E Red hold no `epico-check run`; check-reuse.md names the excluded runs, the modes, stats and the routed callers; executor.md steps 4–5, auditor.md, lean-route.md, validate-mode.md route; run-mode.md has two or more pointers and stays under 500 lines; `epico-check` is distinct from `epico-checkpoint`
    - Validation: `bats tests/check-reuse-routing.bats tests/file-size.bats`
    - Requirements: R6.1, R6.2
    - Quality: Q3
    - Commit: "feat(030): route repeatable check runs through epico-check"

- [x] 8 - Gate guidance
  - _Complexity: Simple | Tests: Unit + Integration | Risks: None | Dependencies: None_
  - Objective: gates are written one per target and never switch a tool's own cache off

  - [x] 8.1 - One gate per target and the cache rules
    - Context:
      - Files: `references/quality-catalog.md` (the sentence starting "The first backtick span of a gate is the whole command validate runs"), `references/tasks.md` ("Generated Quality Gates"), `tests/quality-catalog.bats` (line 75)
    - Objective: the guidance directs one gate line per target sharing the `Qn`, and names the cache flags never to use
    - ToDo:
      - **`quality-catalog.md`:**
        - Replace the clause "a check over several targets or jobs as one command that loops over them — `for t in a b; …`" with: one gate line per target, sharing the legend's `Qn`, each with distinct text before the colon (`- [ ] Q5 — Unit tests (api): …` / `(web): …`).
        - Keep the first-span rule.
        - Add a subsection on gates and caches:
          - name tool and flag together, never a bare flag: turbo `TURBO_FORCE`/`--force`, nx `--skip-nx-cache`, jest `--no-cache`, pytest `--cache-clear`, gradle `--rerun-tasks`/`--no-build-cache`;
          - `go test -count=1` only for tests that read external state;
          - prefer incremental modes (Stryker `incremental`);
          - no gate runs a command another gate already runs — e.g. a `make test` that already runs the unit suite, beside a `make test-unit` gate;
          - no real project names in examples.
      - **`tasks.md` "Generated Quality Gates":** "one or more boxes per legend line — one per target".
      - **Existing case:** update `tests/quality-catalog.bats:75`.
      - **Regression guard:** copy the authored `gates-shared-qn.bats` too. The behaviour it guards (two lines sharing a `Qn`, each closed by its own prefix, an ambiguous prefix refused) already holds, so it has no Red (Test Advisor escalation).
    - Tests: Unit · `tests/gate-guidance.bats` — the loop clause is gone; `--no-cache` never appears without its tool; a shared Qn with distinct prefixes; each tool+flag pair; `go test -count=1` for external state; incremental, Stryker and another gate; the first-span rule kept; tasks.md "one or more boxes per … one per target"
    - Validation: `bats tests/gate-guidance.bats tests/gates-shared-qn.bats tests/quality-catalog.bats`
    - Requirements: R7.1, R7.2, R7.3, R7.4
    - Quality: Q3
    - Commit: "feat(030): one gate per target and native-cache guidance"

- [x] 9 - Contracts, README and the local check
  - _Complexity: Moderate | Tests: Integration | Risks: act needs a clean clone, never a worktree | Dependencies: Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8_
  - Objective: the producers and consumers agree, the new command and runtime are documented, and the whole local check passes

  - [x] 9.1 - Producer→consumer contracts
    - Context:
      - Files: `scripts/check-reuse.sh`, `scripts/validate-run.sh`, `scripts/run-report.sh`, `scripts/report.sh`, `scripts/hook-reuse-guard.sh`
    - Objective: the keys `check-reuse.sh run` emits are the ones `validate-run.sh` reads; the reports carry every field their readers read; the guard and the runner resolve one ledger directory
    - ToDo:
      - **Test:** copy the authored contract test.
      - **On a mismatch,** fix the producing script, never the test.
    - Tests: Integration · `tests/check-reuse-contracts.bats` — evidence and fingerprint flow from check-reuse into validate-run; timeout reaches the detail; the reused decision becomes the reused flag; report.sh counts and verdict; run-report.sh gate lines; check-reuse and the guard resolve the same ledger dir from both worktrees
    - Validation: `bats tests/check-reuse-contracts.bats`
    - Requirements: R1.5, R2.8, R4.1
    - Quality: Q1, Q3

  - [x] 9.2 - README, runtime floor and CHANGELOG
    - Context:
      - Files: `README.md` (command list and runtime line), `CHANGELOG.md`
    - Objective: the README names `epico-check` and the profile, and declares git 2.31 or newer
    - ToDo:
      - **README command list:** add `epico-check` (`run`, `lookup`, `stats`, `profile --detect`) and `.epico/reuse-profile.json` (`mode` off | shadow | on).
      - **Runtime line:** declare git 2.31 or newer beside Claude Code 2.1.295.
      - **CHANGELOG:** an Unreleased entry, with no project names.
    - Tests: None — the Validation grep is the check; the CHANGELOG has no testable behaviour
    - Validation: `grep -q 'epico-check' README.md && grep -q 'git 2.31' README.md`
    - Quality: Q6, Q7

  - [x] 9.3 - The whole local check from a clean clone
    - Context:
      - Files: `RELEASING.md` (the local recipe), `.epico/constitution.md` (Quality: the CI mirror line)
    - Objective: every gate of this story passes on this machine before any push
    - ToDo:
      - **Where:** from a clean clone, never a git worktree (its `.git` points outside the act mount).
      - **Run:**
        - `shellcheck scripts/*.sh bin/*`;
        - `bats tests/` as a normal user;
        - `docker build -t epico-act:26.04 ci/act-ubuntu-26.04` once, then the four `act -P ubuntu-26.04=epico-act:26.04 --pull=false -j <job>` runs (`shellcheck`, `bats`, `validate-examples`, `plugin-validate`);
        - `pre-commit run --all-files`;
        - `claude plugin validate --strict`;
        - `gitleaks git .`;
        - `trivy fs .`.
      - **Record each result.** Fix a red in the owning sub-task's files, never by weakening a check.
    - Tests: None — verification only; it runs the whole suite
    - Validation: `shellcheck scripts/*.sh bin/* && bats tests/`
    - Quality: Q1, Q3, Q4, Q5, Q9, Q10, Q12

  - Commit: "docs(030): document epico-check, the reuse profile and git 2.31"

- [x] 10 - Regression guards for the review findings
  - _Complexity: Moderate | Tests: Integration | Risks: a guard that cannot fail proves nothing; the fixes shipped before their tests | Dependencies: Task 3, Task 6_
  - Objective: every defect the technical review found has a permanent test, and each test is shown to fail when its fix is removed

  - [x] 10.1 - Concurrency, signals and a command that cannot start
    - Context:
      - Files: `scripts/check-reuse.sh` (`ledger_lock`, `ledger_record`, `ledger_write`, `run_command`, `cleanup`), `tests/lib/reuse-fixture.sh`, `.draft/reports/tech-review-3.x.md`
    - Objective: an older PASS never replaces a newer FAIL, a terminated runner leaves no command behind, and a command that cannot start records nothing
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-concurrency.bats`.
      - **On a failing guard,** fix the producing script, never the test.
    - Tests: Integration · `tests/check-reuse-concurrency.bats` — a FAIL recorded while six PASS writers run on the same key is not overwritten by an older PASS; twelve parallel runs on distinct keys keep twelve entries and leave no lock behind; a lock older than a minute is broken and the result recorded; a lock that stays held keeps the verdict and exit code and warns; a command that cannot start (an unusable TMPDIR, no `setsid`) is FAIL with exit 126, records nothing and leaves a recorded PASS in place; a TERM to the runner stops the checked command and leaves no temp file
    - Validation: `bats tests/check-reuse-concurrency.bats`
    - Requirements: R2.15, R2.16, R4.8
    - Quality: Q1, Q2, Q3, Q8

  - [x] 10.2 - Hostile probes, profiles and inputs
    - Context:
      - Files: `scripts/check-reuse.sh` (`load_profile`, `run_probe`, `build_key`), `tests/lib/reuse-fixture.sh`, `.draft/reports/tech-review-2.1-2.2.md`
    - Objective: no probe, profile or input can leave the key unchanged when the environment changed, or break the runner
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-hostile-key.bats`.
      - **On a failing guard,** fix the producing script, never the test.
    - Tests: Integration · `tests/check-reuse-hostile-key.bats` — 200 KB of probe output still gives a key that changes with the output; a probe with an environment prefix (`VAR=1 tool --version`) changes the key when the tool's output changes; a relative probe gives the same key from the top level and from a subdirectory; no `timeout` binary gives no key and a reason naming it; a profile holding several JSON documents, or a tool holding a newline, is read as invalid, and a version-2 first document saying `on` is never read as `on`; a FIFO input gives no key and does not hang; `EPICO_REUSE_PROBE_TIMEOUT=0` means the default 10
    - Validation: `bats tests/check-reuse-hostile-key.bats`
    - Requirements: R2.5, R2.11, R2.13, R4.4
    - Quality: Q1, Q2, Q3, Q11

  - [x] 10.3 - Ledger, shadow log, stats and fingerprint edges
    - Context:
      - Files: `scripts/check-reuse.sh` (`ledger_write`, `shadow_append`, `cmd_stats`, `cmd_lookup`, `fingerprint`, `cmd_profile`), `tests/lib/reuse-fixture.sh`, `.draft/reports/tech-review-3.x.md`
    - Objective: the bounded files, the summary and the fingerprint keep their promises at their edges
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-edges.bats`.
      - **On a failing guard,** fix the producing script, never the test.
    - Tests: Integration · `tests/check-reuse-edges.bats` — a full ledger keeps the entry just written even when every other entry has a later `at`; a 100 KB command is recorded; a shadow.log without a final newline loses no record; `stats` skips garbage lines and a non-numeric `secs`, and gives zeros with a warning for an unreadable log; `lookup` never sets an unreadable ledger aside; a dirty nested repository gives no fingerprint and a clean one does; a TMPDIR inside the work tree leaves the fingerprint stable; a `packageManager` value that is not a plain tool name never becomes a probe
    - Validation: `bats tests/check-reuse-edges.bats`
    - Requirements: R2.11, R3.2, R3.4, R4.3, R5.1
    - Quality: Q1, Q2, Q3, Q8

  - [x] 10.4 - The whole local check again
    - Context:
      - Files: `RELEASING.md` (the local recipe)
    - Objective: the new tests join a suite that passes as a whole
    - ToDo:
      - **Run** `shellcheck scripts/*.sh bin/*` and `bats tests/` as a normal user, from a clean clone.
      - **Record each result.** Fix a red in the owning sub-task's files, never by weakening a check.
    - Tests: None — verification only; it runs the whole suite
    - Validation: `shellcheck scripts/*.sh bin/* && bats tests/`
    - Quality: Q1, Q3

  - Commit: "test(030): regression guards for the review findings"

- [x] 11 - Validation fixes — round 1
  - _Complexity: High | Tests: Integration | Risks: a lock wait that never gives up hangs the runner; a void marker that is never read, or never cleared, changes reuse in silence | Dependencies: Task 10_
  - Objective: the two reds the CI mirror (`act -j bats`) found in the Task 10 guards are fixed where they are produced, and the suite passes on a clean runner

  - [x] 11.1 - A nested repository commits with the fixture's identity
    - Context:
      - Files: `tests/check-reuse-edges.bats` (the nested-repository case), `tests/lib/reuse-fixture.sh` (`commit_all`)
    - Objective: the nested-repository case runs on a machine with no git identity, as the CI runner is
    - ToDo:
      - **Commit the inner repository** with `-c user.email=t@example.invalid -c user.name=t`, as `commit_all` does for the outer one. Setup only: no assertion changes.
    - Tests: None — setup repair of an existing guard; the Validation runs it with no git identity
    - Acceptance: with no git identity on the machine, `tests/check-reuse-edges.bats` passes
    - Validation: `env -u EMAIL -u XDG_CONFIG_HOME HOME="$(mktemp -d)" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true bats tests/check-reuse-edges.bats`
    - Requirements: R2.11
    - Quality: Q3

  - [x] 11.2 - The ledger lock waits while it changes hands, and a dropped FAIL voids its key
    - Context:
      - Files: `scripts/check-reuse.sh` (`ledger_lock`, `ledger_unlock`, `ledger_record`, `ledger_write`, `prepare`, `cleanup`), `tests/check-reuse-concurrency.bats`, `tests/lib/reuse-fixture.sh`
    - Objective: a newer FAIL is recorded however many writers queue for the lock, and a result the lock kept out never leaves an older PASS reusable
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-lock.bats`.
      - **The holder names itself:** right after its `mkdir`, the holder writes a token to `ledger.lock/owner`; release removes the token, then the directory.
      - **The wait counts one holder:** the ~5 s budget restarts whenever the owner token changes; a lock with one owner, or none, past the budget still gives up, records nothing and warns.
      - **A dropped non-PASS voids its key:** on that give-up, create `void.<key>` beside the ledger; `prepare` never reports a hit for a voided key; the next locked write for that key removes the marker. A marker that cannot be written is named in the warning.
      - **Design:** record the lock change with `epico-deviation`, with a follow-up to refine `design.md` (Ledger) and R4.8.
    - Tests: Integration · `tests/check-reuse-lock.bats` — a lock that changes hands for longer than the wait does not make a FAIL's record give up, and the ledger holds the FAIL; a lock held by one owner past the wait leaves the FAIL unrecorded, yet the key's earlier PASS is not reused in mode `on` (decision `ran`); the next recorded run of that key clears the void, and a PASS recorded after it is reused again; release leaves no `ledger.lock` behind
    - Validation: `bats tests/check-reuse-lock.bats tests/check-reuse-concurrency.bats`
    - Requirements: R4.8, R4.9
    - Quality: Q1, Q2, Q3, Q8

  - Commit: "fix(030): keep a newer FAIL under lock contention, and commit the nested repo with an identity"

- [x] 12 - Ledger lock hardening
  - _Complexity: High | Tests: Integration | Risks: a void that is never cleared silently turns reuse off for a key; a release that checks the token wrongly leaves a lock behind for a minute | Dependencies: Task 11_
  - Objective: the four gaps the 11.2 technical review left open are closed — no dropped non-PASS leaves a PASS reusable, voids stay bounded, the wait always ends, and a run only ever releases its own lock

  - [x] 12.1 - A dropped non-PASS voids its key on every path, and a void is named and bounded
    - Context:
      - Files: `scripts/check-reuse.sh` (`ledger_record`, `ledger_write`, `ledger_void`, `prepare`, `cmd_lookup`), `tests/check-reuse-lock.bats`, `tests/lib/reuse-fixture.sh`, `.draft/reports/tech-review-11.2.md` (W3, I1)
    - Objective: a non-PASS that a failed write under the lock drops leaves no reusable PASS, the reason says when a key is void, and markers never outnumber ledger entries
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-void.bats`.
      - **Every dropped non-PASS voids:** the `mktemp`, `jq` and `mv` failure paths of `ledger_write` void the key, as the lock give-up does.
      - **The reason names the void:** `run` and `lookup` say the key is void when a void forced the miss.
      - **Bounded:** each locked write removes the `void.*` markers whose key has no entry in the ledger it wrote.
    - Tests: Integration · `tests/check-reuse-void.bats` — a FAIL whose rewrite fails under the lock leaves the earlier PASS unreused in mode `on`; `lookup` on a voided key reports `would_reuse` false and a reason naming the void; a void whose key the ledger no longer holds is removed by the next recorded run of any key; a void whose key is in the ledger survives another key's run
    - Validation: `bats tests/check-reuse-void.bats tests/check-reuse-lock.bats`
    - Requirements: R4.9, R4.12
    - Quality: Q1, Q2, Q3, Q8

  - [x] 12.2 - The lock wait always ends, and release removes only its own lock
    - Context:
      - Files: `scripts/check-reuse.sh` (`ledger_lock`, `ledger_unlock`, `cleanup`), `tests/check-reuse-concurrency.bats`, `tests/check-reuse-lock.bats`, `.draft/reports/tech-review-11.2.md` (W1, I6)
    - Objective: a stale lock that cannot be broken ends the wait with a warning, and a run whose lock was broken as stale never removes the new holder's lock
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-lock-release.bats`.
      - **Give up on an unmovable stale lock:** when the stale lock cannot be moved aside and is still there and still stale, `ledger_lock` returns 1 instead of resetting its tries.
      - **Release checks the token:** `ledger_unlock` and `cleanup` remove `owner` and the directory only while `owner` still holds this run's token.
    - Tests: Integration · `tests/check-reuse-lock-release.bats` — a stale lock in a ledger directory the runner cannot write ends the wait within 15 s, warns that the result was not recorded, and keeps the check's verdict and exit code; a run whose lock was broken as stale and taken by another holder leaves that holder's `ledger.lock` and `owner` in place when it releases
    - Validation: `bats tests/check-reuse-lock-release.bats tests/check-reuse-lock.bats tests/check-reuse-concurrency.bats`
    - Requirements: R4.10, R4.11
    - Quality: Q1, Q2, Q3, Q8

  - [x] 12.3 - The whole local check
    - Context:
      - Files: `RELEASING.md` (the local recipe)
    - Objective: the hardened lock joins a suite that passes as a whole
    - ToDo:
      - **Run** `shellcheck scripts/*.sh bin/*` and `bats tests/` as a normal user.
      - **Record each result.** Fix a red in the owning sub-task's files, never by weakening a check.
    - Tests: None — verification only; it runs the whole suite
    - Validation: `shellcheck scripts/*.sh bin/* && bats tests/`
    - Quality: Q1, Q3

  - Commit: "fix(030): void every dropped non-PASS, bound the voids, end the lock wait and release only our own lock"

- [x] 13 - The owner file decides who holds the ledger lock
  - _Complexity: High | Tests: Integration | Risks: a claim that loses must never remove the winner's directory; a create that cannot be made must not spin forever | Dependencies: Task 12_
  - Objective: one run holds the ledger lock at a time on any coreutils — uutils' `mkdir` included — and the CI mirror's parallel-writer cases pass

  - [x] 13.1 - Claim the lock with an O_EXCL owner file
    - Context:
      - Files: `scripts/check-reuse.sh` (`ledger_lock`, `ledger_unlock`), `tests/check-reuse-concurrency.bats`, `tests/check-reuse-lock.bats`, `tests/check-reuse-lock-release.bats`, `tests/lib/reuse-fixture.sh`
    - Objective: a run that creates the lock directory holds the lock only if it also creates the owner file, so a `mkdir` that lets several racers succeed still lets one holder in
    - ToDo:
      - **Test:** copy the authored test from `.draft/authored-tests/tests/check-reuse-lock-claim.bats`.
      - **Claim:** after `mkdir`, create `ledger.lock/owner` with the token under `set -o noclobber` (bash opens it `O_EXCL`); that create, not the `mkdir`, takes the lock.
      - **Lose cleanly:** a run whose create fails runs `rmdir` on the lock — which refuses a directory holding another run's owner — and goes on waiting; a token that cannot be created is no lock, so drop the empty-token fallback.
    - Tests: Integration · `tests/check-reuse-lock-claim.bats` — with a `mkdir` on PATH that succeeds on an existing directory (uutils' race at its worst), twelve parallel runs on distinct keys keep twelve entries and leave no lock behind; a FAIL recorded while six PASS writers run on the same key wins and every writer's entry is kept; a run that finds another run's owner file in a directory its own `mkdir` reported as created leaves that owner in place and records after it releases
    - Validation: `bats tests/check-reuse-lock-claim.bats tests/check-reuse-lock.bats tests/check-reuse-lock-release.bats tests/check-reuse-concurrency.bats`
    - Requirements: R4.8, R4.11
    - Quality: Q1, Q2, Q3, Q8

  - [x] 13.2 - The whole local check and the CI mirror
    - Context:
      - Files: `RELEASING.md` (the local recipe), `.github/workflows/shell.yml` (the `bats` job)
    - Objective: the suite passes on this machine and on the CI image, where uutils' `mkdir` races
    - ToDo:
      - **Run** `shellcheck scripts/*.sh bin/*`, then the CI mirror's `bats` job, as a normal user.
      - **Record each result.** Fix a red in the owning sub-task's files, never by weakening a check.
    - Tests: None — verification only; the CI mirror runs the whole suite on Ubuntu 26.04
    - Validation: `shellcheck scripts/*.sh bin/* && act -P ubuntu-26.04=epico-act:26.04 --pull=false -j bats`
    - Quality: Q1, Q3, Q9

  - Commit: "fix(030): the owner file, created with O_EXCL, decides who holds the ledger lock"

## Quality Gates

- [ ] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [x] Error handling implemented
- [x] Q1 — Lint: `shellcheck scripts/*.sh bin/*` exits 0
- [x] Q2 — Error handling: every new or changed script runs under `set -euo pipefail` and refuses with its reason in its JSON, or, for a usage error (exit 2), on stderr with no JSON; the story's bats cases prove each refusal path
- [x] Q3 — Unit tests: `bats tests/` passes, as a normal user
- [x] Q4 — Dependency vulnerabilities (SCA): `trivy fs .` reports no HIGH or CRITICAL
- [x] Q5 — Secrets: `gitleaks git .` reports no leaks
- [x] Q6 — README: `grep -q 'epico-check' README.md` exits 0
- [x] Q7 — Supported and declared runtime: `grep -q 'git 2.31' README.md` exits 0
- [x] Q8 — Data integrity: the ledger and the shadow log are written through a temp file and a rename; a missing, corrupted or wrong-shaped ledger, log or profile never crashes the check runner and is never overwritten in place; a failed save says so and keeps the check's verdict
- [x] Q9 — CI mirror (shellcheck): `act -P ubuntu-26.04=epico-act:26.04 --pull=false -j shellcheck` passes from a clean clone
- [x] Q9 — CI mirror (bats): `act -P ubuntu-26.04=epico-act:26.04 --pull=false -j bats` passes from a clean clone
- [x] Q9 — CI mirror (validate-examples): `act -P ubuntu-26.04=epico-act:26.04 --pull=false -j validate-examples` passes from a clean clone
- [x] Q9 — CI mirror (plugin-validate): `act -P ubuntu-26.04=epico-act:26.04 --pull=false -j plugin-validate` passes from a clean clone
- [ ] Q10 — Pre-commit hook: `pre-commit run --all-files` passes
- [x] Q11 — Format version: the ledger and the profile carry `version: 1`; a file of another version is set aside (ledger) or read as absent (profile), never misread
- [x] Q12 — Plugin schema: `for p in .claude-plugin/plugin.json .claude-plugin/marketplace.json skills agents; do claude plugin validate --strict "$p" || exit 1; done` passes
