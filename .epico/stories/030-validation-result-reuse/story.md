---
story: 030-validation-result-reuse
type: feature
scale: full
engineering: project
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

# Story - Validation Result Reuse

## Introduction

A story's checks run again and again on code that has not changed. A validation command passes in the Executor, runs again at the end of the run, again in Validate, and again in the Auditor's reproductions, and each repetition costs minutes on a real project. This story lets the Epico reuse a passing result when the command, the code and the environment are identical to its last passing run. Every project starts in a measuring-only shadow mode, so the gain and any disagreement are seen before anything is skipped. The story also closes a revalidation hole that today can report a story as passing on a fraction of its checks, and it rewrites the gate guidance so checks can be reused per target.

## Requirements

### R1. Revalidation integrity

**User Story:** As a developer revalidating a story after a fix, I want only unchanged passing checks kept, so that a revalidation can never pass on checks it did not settle.

#### Acceptance Criteria

- R1.1: WHEN a revalidation of named entries (`--only`) is requested for a story that has no previous validation run THE SYSTEM SHALL refuse with exit code 2, write no report, and name a full validation as the first step
- R1.2: WHEN a revalidation of named entries meets an unselected entry that passed on code that has changed since THE SYSTEM SHALL run that entry again instead of keeping its previous result
- R1.3: WHEN a revalidation of named entries meets an unselected entry that passed on the same code THE SYSTEM SHALL keep its previous result without running it
- R1.4: WHEN a revalidation of named entries meets an unselected passing entry that carries no code fingerprint, or whose current fingerprint cannot be determined THE SYSTEM SHALL run that entry again
- R1.5: THE SYSTEM SHALL keep every field the validation report carries today and add, per entry, whether it was reused and the code fingerprint it was settled on

### R2. Exact reuse of a passing check

**User Story:** As a developer, I want a check that already passed on this exact code and environment returned without running again, so that repeated validations cost seconds instead of minutes.

#### Acceptance Criteria

- R2.1: WHILE a project's reuse mode is `on`, WHEN a check is requested whose command, code and environment equal those of its last passing run THE SYSTEM SHALL return that PASS without running the command and report it as reused
- R2.2: WHEN a check is requested whose last recorded result for the same command, code and environment is a FAIL THE SYSTEM SHALL run the command
- R2.3: WHEN a check is requested after a tracked file, or an untracked file git does not ignore, changed since its last PASS THE SYSTEM SHALL run the command
- R2.4: WHEN a check is requested after a file listed among the profile's inputs changed since its last PASS THE SYSTEM SHALL run the command, although git ignores that file
- R2.5: WHEN a check is requested after the output of one of the profile's tool-version probes changed since its last PASS THE SYSTEM SHALL run the command
- R2.6: WHEN a check is requested after the reuse profile itself changed since its last PASS THE SYSTEM SHALL run the command
- R2.7: WHEN only files under `.epico/` or `.epic/` changed since a check's last PASS THE SYSTEM SHALL treat the code as unchanged, whether those directories are versioned, gitignored, or gitignored while holding a tracked file
- R2.8: WHEN a check passed in one worktree of a repository THE SYSTEM SHALL reuse that PASS for the same check, code and environment in another worktree of the same repository
- R2.9: WHEN a check is requested with `--fresh` THE SYSTEM SHALL run the command and replace its recorded result
- R2.10: IF a check's command contains an entry of the profile's never-reuse list THEN THE SYSTEM SHALL run it every time and record nothing reusable for it
- R2.11: IF the directory is not a git work tree, the code fingerprint cannot be computed, a submodule holds uncommitted changes, or a profile input exists but cannot be read THEN THE SYSTEM SHALL run the command and report why no reuse was possible
- R2.12: WHEN a reused or run check is reported THE SYSTEM SHALL return the same verdict and exit code a direct run would return: 0 for PASS, 1 for FAIL, and FAIL with `timed out after <s>s` when the command exceeds its timeout
- R2.13: IF a tool-version probe runs longer than 10 seconds THEN THE SYSTEM SHALL stop it, run the check, and report that no reuse was possible, naming the probe
- R2.14: WHEN a check is reported in any mode, a never-reuse command included THE SYSTEM SHALL report the code fingerprint whenever it can be computed
- R2.15: IF the command cannot be started THEN THE SYSTEM SHALL report FAIL with exit code 126 and record nothing
- R2.16: WHEN the check runner is terminated THE SYSTEM SHALL stop the command it started

### R3. Shadow measurement

**User Story:** As a developer, I want each project to measure what reuse would skip before anything is skipped, so that I switch reuse on from evidence and not from trust.

#### Acceptance Criteria

- R3.1: WHILE a project's reuse mode is `shadow` — the default, also when the project has no reuse profile — THE SYSTEM SHALL run every check and record whether it would have been reused
- R3.2: WHEN the shadow summary is requested THE SYSTEM SHALL report the number of runs, how many would have been reused, the seconds those runs took, and every disagreement — a check that would have been reused as PASS but failed when run — with its command and UTC timestamp
- R3.3: WHILE a project's reuse mode is `off` THE SYSTEM SHALL run every check and record nothing
- R3.4: THE SYSTEM SHALL keep at most 2000 recorded results and 5000 shadow lines per repository, dropping the oldest first

### R4. Ledger integrity

**User Story:** As a developer, I want the record of passing checks written only by the check runner and never broken by a bad file, so that a reused PASS always stands for a run that happened.

#### Acceptance Criteria

- R4.1: WHEN an agent writes or edits a file inside the repository's reuse ledger directory THE SYSTEM SHALL refuse the write and name the rule that only the check runner writes there
- R4.2: WHEN an agent runs a shell command that redirects, copies, moves or deletes into the reuse ledger directory THE SYSTEM SHALL refuse the command, whatever else it runs
- R4.7: IF recording a shadow line fails, or setting an unreadable ledger aside fails THEN THE SYSTEM SHALL still run the check, return its own verdict and exit code, and warn
- R4.3: IF the ledger file is missing, not valid JSON, wrong in shape or of an unknown format version THEN THE SYSTEM SHALL run checks as if nothing were recorded and set an existing unreadable file aside under a new timestamped name, never replacing an earlier set-aside copy
- R4.4: IF the reuse profile is not valid JSON or carries an unknown format version THEN THE SYSTEM SHALL apply the shadow defaults, warn, and leave the profile file unmodified
- R4.5: IF recording a result fails THEN THE SYSTEM SHALL still return the check's own verdict and exit code and warn that the result was not recorded
- R4.6: IF the reuse guard fails while deciding THEN THE SYSTEM SHALL let the tool call through
- R4.8: WHEN several checks record a result at once THE SYSTEM SHALL keep each one, however many queue for the ledger lock, and never let an older result replace a newer one for the same key
- R4.9: IF a non-PASS result cannot be recorded THEN THE SYSTEM SHALL not reuse the earlier PASS for the same key until a later run of that key is recorded
- R4.10: IF a stale ledger lock cannot be broken THEN THE SYSTEM SHALL stop waiting, warn, and return the check's own verdict and exit code
- R4.11: WHEN a run releases the ledger lock THE SYSTEM SHALL remove it only while the lock's owner token is still the run's own
- R4.12: WHEN a result is recorded THE SYSTEM SHALL remove every void marker whose key has no ledger entry

### R5. Per-project profile

**User Story:** As a developer adopting the Epico on any stack, I want the reuse key fitted to my project's toolchain and local files, so that reuse is correct whatever the language.

#### Acceptance Criteria

- R5.1: WHEN profile detection runs THE SYSTEM SHALL propose one version probe for each toolchain whose manifest exists in the project and whose binary is on PATH, and write no file
- R5.2: WHEN profile detection runs THE SYSTEM SHALL propose as inputs the gitignored environment and local-configuration files that exist outside dependency directories
- R5.3: WHEN init, or init with repair, runs on a project with no reuse profile THE SYSTEM SHALL show the detected profile and write it in shadow mode
- R5.4: WHEN the project health summary runs on a project with an `.epico/` directory and no reuse profile THE SYSTEM SHALL warn and name the command that creates one
- R5.5: IF profile detection meets a manifest it cannot parse, or a directory that is not a git work tree THEN THE SYSTEM SHALL skip what it cannot read, warn, and still print a profile

### R6. Routing

**User Story:** As a maintainer of the Epico, I want every repeatable check routed through reuse and every must-fail or clean-copy run kept out of it, so that reuse saves time without weakening any guard.

#### Acceptance Criteria

- R6.1: THE SYSTEM SHALL run the Executor's validation commands, the inline route's validation commands, the end-of-run gates, the Auditor's claim reproductions and the lean route's whole check through the check runner
- R6.2: THE SYSTEM SHALL run outside reuse every run that must observe a failure or must run outside the working tree: the Test Advisor's Red runs, the deferred end-to-end Red run, the bugfix guard on the base commit and the final reviewer's clean-copy run

### R7. Gate guidance

**User Story:** As a developer whose quality item covers several suites, I want one gate per suite, so that an unchanged suite is reused while a changed one runs.

#### Acceptance Criteria

- R7.1: WHEN a quality item is checked over several targets THE SYSTEM SHALL direct the story author to write one gate line per target, sharing the item's `Qn`, each with distinct text before the colon
- R7.2: WHEN a story carries two gate lines that share one `Qn` THE SYSTEM SHALL validate the story without error and close each gate by its own text prefix
- R7.3: THE SYSTEM SHALL state in its gate guidance that a gate never switches a tool's own result cache off, naming each tool together with its flag (satisfied-by: references/quality-catalog.md)
- R7.4: THE SYSTEM SHALL state in its gate guidance that no gate runs a command another gate of the same story already runs (satisfied-by: references/quality-catalog.md)

## Quality Requirements

- Q1: Lint — `shellcheck scripts/*.sh bin/*` exits 0
- Q2: Error handling — every new or changed script runs under `set -euo pipefail` and refuses with its reason in its JSON, or, for a usage error (exit 2), on stderr with no JSON; the story's bats cases prove each refusal path
- Q3: Unit tests — `bats tests/` passes, as a normal user
- Q4: Dependency vulnerabilities (SCA) — `trivy fs .` reports no HIGH or CRITICAL (the plugin has no dependencies)
- Q5: Secrets — `gitleaks git .` reports no leaks
- Q6: README — `grep -q 'epico-check' README.md` exits 0: the README names the check runner and the reuse profile beside the other commands
- Q7: Supported and declared runtime — `grep -q 'git 2.31' README.md` exits 0: git 2.31 or newer (for absolute common-dir paths) is declared beside Claude Code 2.1.295 (signal: a new runtime floor)
- Q8: Data integrity — the ledger and the shadow log are written through a temp file and a rename; a missing, corrupted or wrong-shaped ledger, log or profile never crashes the check runner and is never overwritten in place; a failed save says so and keeps the check's verdict
- Q9: CI mirror — the four CI jobs (`shellcheck`, `bats`, `validate-examples`, `plugin-validate`) pass under `act -P ubuntu-26.04=epico-act:26.04 --pull=false` from a clean clone. One gate per job, as R7.1 directs (signal: `.github/workflows/`)
- Q10: Pre-commit hook — `pre-commit run --all-files` passes (signal: a git repository, at `project`)
- Q11: Format version — the ledger and the profile carry `version: 1`; a file of another version is set aside (ledger) or read as absent (profile), never misread (signal: files the program reads back)
- Q12: Plugin schema — `claude plugin validate --strict` passes (signal: `hooks/hooks.json` gains a matcher)

Not exercised by this story, each with its reason:
- Formatting: omitted by the constitution; the scripts were never `shfmt`-formatted.
- Types: bash has no type checker.
- Lockfile, dependencies justified: the plugin installs nothing and this story adds nothing.
- `.gitignore` and `.editorconfig`: unchanged; the ledger lives under the git dir.
- Hardened workflows, licence/SBOM/signing, security policy, branch protection, minimum dependency age: no change to workflows, distribution or dependencies.

## Success Metrics

- On a repository of up to 5000 tracked files, computing the reuse key adds at most 50 ms per check. Measured today: 8–20 ms on five repositories.
- In mode `on`, a Validate run started right after a passing end-of-run gate pass, with no code change, runs 0 of the commands that passed.
- Across the first three projects switched from `shadow` to `on`, every disagreement in the shadow summary is traced to a flaky check or an external-state check that belongs on the never-reuse list, and none to the reuse key.

## Constraints

- [CONSTITUTION] Scripts depend on bash, jq and git only — plus `setsid` and `timeout`, which `validate-run.sh` already uses; no new runtime dependency.
- [CONSTITUTION] Every new script speaks one JSON contract on stdout, documented in its header; exit 0/1/2 mean done/refused/bad usage; it is called through a `bin/epico-*` wrapper by bare name from references.
- [CONSTITUTION] Hooks never block a session on their own failure.
- [CONSTITUTION] TDD: every bats case is written first and seen failing; tests use real temp directories and real git repos.
- git 2.31 or newer is required for absolute common-dir paths.
- The reuse profile is JSON: jq is the only parser the scripts may use.
- Report fields are additive only: the readers of `validation-run.json` and `validation-report.yaml` keep working unchanged.
- `references/run-mode.md` stays within the 500-line limit enforced by `tests/file-size.bats`; new prose lives in a new reference.
- Project-agnostic: nothing this story ships — code, references, agent text, tests or examples — names a real project; guidance describes cases, and each project is analysed on its own.
- The name "checkpoint" belongs to checkpoint mode; this feature uses "reuse" and "ledger".

## Out of Scope

- Per-check scopes and selective re-run of only the checks a change touches (a follow-up story).
- Expiry times for checks that depend on external state, such as vulnerability databases (a follow-up story; this story offers only the never-reuse list).
- A policy for flaky checks beyond reporting disagreements (a follow-up story).
- Running gates in parallel.
- Switching a project from `shadow` to `on` automatically.
- Sharing the ledger across machines or with CI.
- Detecting never-reuse commands automatically; the list is written at init by the requester.
