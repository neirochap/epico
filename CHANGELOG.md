# Changelog

All notable changes to the Epico plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each release notes the **minimum Claude Code version** it requires. From 0.14.0
on there is one floor for the whole plugin (see README "Prerequisites").

## [Unreleased]

Checks that already passed on the same code are no longer run again, once a project asks for it.

**Minimum Claude Code:** 2.1.295, unchanged. **Minimum git:** 2.31 (new; it names the common git directory by absolute path).

### Added

- **`epico-check`: exact reuse of a passing check.** `epico-check run -- <cmd>` returns the PASS of an earlier run whose command, code and environment are identical, without running the command; a FAIL always runs. The key covers every tracked file and every untracked file git does not ignore (`.epico/` and `.epic/` excluded), the output of the profile's tool-version probes, the content of the profile's listed inputs and the profile itself. The ledger is shared by every worktree of a repository, written through a temp file and a rename under a lock, and only `epico-check run` writes it — a PreToolUse guard denies an agent's direct write. Also `lookup`, `stats` and `profile --detect`.
- **Shadow mode is the default.** Every project measures first: all checks run, and `epico-check stats` reports what reuse would have skipped and every disagreement. Switching to `on` is a person's decision.
- **`.epico/reuse-profile.json`**, written by `init` and `init --repair`: `mode`, `tools`, `inputs` and `never`. `epico-doctor` warns when it is missing.
- **`references/check-reuse.md`**, the single home of which runs are routed through reuse and which never are (the ones that must observe a failure, or run outside the working tree).

### Fixed

- **`epico-validate-run --only` could pass a story on a fraction of its checks.** With no previous full run it now refuses (exit 2); and an unselected PASS is kept only on the code it passed on — on changed code, or with no fingerprint to compare, it runs again. Each entry of the report also carries `reused` and `fingerprint`.

### Changed

- **Gate guidance:** one gate line per target, sharing the item's `Qn`, so an unchanged suite is reused while a changed one runs; a gate never switches a tool's own result cache off, and no gate runs a command another gate already runs.

## [0.27.1] — 2026-11-03

The converge pass and the final review run silently.

**Minimum Claude Code:** 2.1.295, unchanged.

### Fixed

- **The converge pass and the final review are never announced**, and the reviewer's English report never reaches the chat. Around these steps English narration had reached a beginner in four of seven instant runs.

## [0.27.0] — 2026-11-03

A fresh reviewer checks a beginner's work before the closing; runs clean up after themselves; routine questions become one list.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- **`final-reviewer` agent**: for a beginner, the lean route's converge pass is a fresh reviewer's. It runs after the commit, reads code it did not write, reports at most three gaps a beginner would hit — each with the command that reproduces it — and never edits; only a finding the main agent reproduces is fixed.

### Changed

- **Host hygiene**: every process a run started is stopped before the closing unless the requester asked to keep it, and nothing opens on the requester's desktop unasked.
- **A beginner's routine round becomes numbered assumptions** confirmed at once — one question instead of three or more.
- `PURPOSE.md` points only to commands every Claude Code has: the `/gsd-*` and `/tab` suggestions are gone.

## [0.26.1] — 2026-11-02

A beginner's closing on the lean route is three lines; the language hook is gone.

**Minimum Claude Code:** 2.1.295, unchanged.

### Changed

- **A beginner's closing on the lean route is three lines** — what to type, what it does, and the one decision that reduced protection most — then the `Not verified:` sentence; the rest goes to the README. On the beginner retest the longest closing fell from 1,060 to 677 characters.

### Removed

- **`hook-language-guard.sh`.** It fires when the turn ends, after the English sentence was shown, so it cannot prevent the leak, and its rewrite made the closing longer. With the lean route back for beginners the leak fell to one run in seven without help from it.

## [0.26.0] — 2026-11-02

The 2026-10-30 SDD battery's P1 verdict: inferences replace three questions, every run ends with a converge pass, a beginner's closing has a ceiling, and nothing leaves the machine unasked.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- **A converge pass ends every run** — the lean route and a story run re-read the request and the floor against what was built; a gap is fixed only after a command reproduces it, and the pass stops at the first one that finds nothing (at most two).
- **`hook-language-guard.sh` (Stop)**: in a session that invoked the epico, an English sentence that reached a requester writing in another language blocks the end of the turn once, and the closing says it again in their language — a rewrite, not a legend.
- **`epico-jargon --max-chars <n>`**: fails a text longer than n characters. A beginner's closing is checked with 600.

### Changed

- **The engineering level is inferred from the whole request, never asked** — stated on the proposal line with how to move it. Using a thing again is not upkeep: a request to keep or reuse something is an `experiment`. A beginner whose request does not settle the level takes the lean route; anyone else takes `tool`. In the battery the asked question chose a 3–5 or a 12–17 minute route by chance.
- **Nothing leaves the machine unless the requester asked for that exact step** — no upload, push, outside login or message, nothing written or deleted outside the project. A check run had uploaded a beginner's project to a public file host after a yes/no question.
- **The interface language is the request's language, stated, not asked** — asked only when the request mixes languages or names readers of another one.
- **Failure cases are listed before the code, one test each**; a case whose test never ran keeps its box open.
- **A web page is checked at the URL its own server printed**, with `curl`, before it is called working.
- **"See it running" shows the output as text** before the next question — never a question right after a question.
- `run-mode.md` is split into `run-status.md` (status transitions) and `run-end.md` (end of run); every reference, skill and agent stays under 500 lines, and a test holds them there.

### Removed

- **No model hint, model choice or run command for a beginner** — the Sonnet line, the run-model question and the `/model` handoff are developer-only.

## [0.25.1] — 2026-10-29

The lean route tests every error rule the request states; the commit guard checks only a session that is running a story.

**Minimum Claude Code:** 2.1.295, unchanged.

### Changed

- **The lean route tests every error rule the request states** — bad input, end of input, the data file — and each floor case, before calling the work done. These are the cases a run with no plan forgets first. On the beginner series the lean route rose from 89 to 94 of 100, above the Fast story it replaced, at about two thirds of its output tokens and wall clock; on an expert's precise spec it scored 87, against 86 before.

### Fixed

- **The commit guard stays silent in a session that is not running a story.** It blocked the end of every turn in any session opened on a repository with a finished, uncommitted group, even one that never used Epico. It now reads the session's transcript and checks only when a Bash tool call in it ran `epico-close`; with no readable transcript it checks as before.

## [0.25.0] — 2026-10-29

Work at engineering level `experiment` is done directly, with the security floor and no story; the commit guard sees commits on worktree branches.

**Minimum Claude Code:** 2.1.295, unchanged.

### Changed

- **Work at engineering level `experiment` takes the lean route and writes no story.** Triage hands it to `references/lean-route.md`: the work is done directly, with no proposal to confirm, no `tasks.md` and no Epico script, while the security floor and the project's whole check before done stay. On the 7-language beginner series it scored as the Fast story did (89 of 100) with less than half the output tokens, about a quarter of the context re-read, about a third of the wall clock and no questions. `tool`, `project` and `product` are unchanged.
- **`instant` is the lean route's direct entrance**: it sets `experiment` without reading it, and writes no story either.

### Fixed

- **The commit guard finds a commit made on a worktree's branch.** It read only the main tree's `HEAD`, so a group committed in a worktree blocked every turn and asked for a duplicate commit.

## [0.24.0] — 2026-10-27

A checkpoint now asks about every runtime dependency the stage added that no decision record names, and the Tech Reviewer walks a fixed set of edge-case questions without a finding quota.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- **`epico-depdiff --base <rev>`** lists the runtime dependencies added between two revisions — `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements.txt`, `Gemfile` and `composer.json`, read from git objects, never the working tree — and marks each one covered when an ADR under `adr/` or `docs/adr/` names it. Dev, test and build dependencies are not counted, and a manifest it cannot read goes to `unparsed` instead of being half-read.
- **Checkpoint step 3 asks about each uncovered dependency**, from the previous checkpoint's commit: record an ADR, accept it without one, or mark it as not a runtime dependency. A refusal from `epico-depdiff` is shown, never read as nothing new.
- **Edge-case questions for the Tech Reviewer** — boundaries, empty and huge input, concurrency, time, partial failure, permissions, retries — each answered in one line in its report. They set no minimum number of findings: zero findings is a valid `PASS`, and the orchestrator never asks for more after one.

### Fixed

- **`epico-validate-run` no longer runs a command holding a `<placeholder>`**, which reported the check as failed; such a span is left to the Auditor. The quality catalog now says a gate's first backtick span is the whole command.
- **`epico-close` refuses a test-first box whose Red is not on record.** At engineering level `project` or `product`, a Standard or Full sub-task with a `Tests:` field closes only with its entry in `.draft/red-evidence.yaml`, so the gap no longer surfaces first at validation.
- **New test cases never go into a file holding another sub-task's pre-authored test.** Added there, they made `epico-test-diff` block that sub-task's close.

## [0.23.1] — 2026-10-24

Memory pages follow the rename to Epico.

**Minimum Claude Code:** 2.1.295, unchanged.

### Fixed

- Memory pages are written under `epico/<type>/` instead of the pre-rename `epic/<type>/`; reads match both prefixes, so pages written before the rename stay visible.
- README install and CI examples point at the `epico` checkout instead of `epic`.

## [0.23.0] — 2026-10-24

Production code stays with the agent that holds the conversation, verification runs from scripts instead of sub-agents, and every language the run detects gets its own secure-coding rules.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- **`epico-validate-run`** runs a story's Validation and generated-gate commands and writes the Auditor's Part 1 report in seconds. The orchestrator runs it before the Auditor: on a failure no sub-agent is spawned, and the Auditor settles only the entries a command cannot (`JUDGE`).
- **`epico-run-report`** writes the run report's skeleton — the recorded line, one line per closed box, the gates, the commits — so the model adds only what no file holds.
- **`epico-wait-port`** waits for a server the run started, in place of `sleep` and retried `curl`. With `--pid` it stops the moment that server exits, instead of waiting out the timeout.
- **`reviewModel`** option for the Auditor and the Tech Reviewer: `inherit` (default), `sonnet` or `haiku`.
- **Secure-coding rules per language** (`references/language-rules.md`). The Executor, the main agent on the inline route and the Tech Reviewer read only the sections of the languages the run detected.
- **Never eval or exec input**, in both agents and in the managed `CLAUDE.md` block: input reaches a shell, an interpreter or a query only as an argument list or a bound parameter.
- **The quality catalog checks the CI mirror, structured logs and the supply chain.** The CI jobs pass locally before a push, mirroring the runner's environment, not just its command. Without Docker or Podman the CI mirror gate is recorded as SKIP (not run), never as FAIL.
- **The audit report names what no test covers** (`untested:`) **and the fidelity rung it ran on** (`verified_at:`), so a green from a low rung is not read as one from a high one.

### Changed

- **One fix round, and its revalidation re-checks only the failures** (`epico-validate-run --only`). The Auditor is spawned again only for a `JUDGE` failure or an audit gap.
- **`epico-close` takes several boxes** in one call, closing them in order and stopping at the first refusal.
- **A sub-agent only gets work that needs nothing from the context window.** A test written from the spec, a disposable probe, a read, a review — sub-agent. Production code, or anything that depends on an answer, decision or finding of the session, runs inline, or in a new session when the context band is `degraded`. The default flipped: a sub-task no row clearly claims now runs inline, where before *anything else* went to a sub-agent. An Executor writes production code only as a member of a parallel group, so `executorModel` applies there and to context-free sub-tasks.
- **A parallel group no longer falls back to `--serial` without a worktree.** The worktree is preferred; without one (no `worktree.baseRef: "head"`, headless, declined) the group runs in the main checkout, since detection already proved it shares no file.
- **A parallel group that shares a build, or edits code outside the session's repository, is refused** and runs inline, one item at a time. Disjoint files are not enough when the items compile together in one output directory, and a worktree of the session's repository holds none of the code that lives outside it.

### Fixed

- **Concurrent writers no longer lose entries on Ubuntu 25.10 and later.** Both locks relied on `mkdir` succeeding for exactly one caller, which uutils coreutils' `mkdir` does not guarantee: on Ubuntu 26.04 two of twelve concurrent writers could both win. The deviation register now locks with a file bash creates under noclobber (`O_EXCL`), and the archive manifest lock lets a winner hold only when its owner marker is the only one in the lock directory.

## [0.22.0] — 2026-10-23

The plugin is now **Epico**, and the quality catalog checks how CI workflows and the repository itself are hardened.

**Minimum Claude Code:** 2.1.295, unchanged.

### Changed

- **BREAKING — the plugin is renamed `epic` → `epico`.** Install it as `epico@lucascouts`, then uninstall `epic@lucascouts`; with both enabled, both load. The command is `/epico:epico`, the agents are `epico:executor`, `epico:auditor` and the rest, and the commands on PATH are `epico-*` (`epico-doctor`, `epico-validate`, …). The project layout follows the name: `.epic/` → `.epico/`, `EPIC.md` → `EPICO.md`, the `epic:index` and `CLAUDE.md` markers → `epico:*`, the `EPIC_*` variables → `EPICO_*`, and `--epic-dir` → `--epico-dir`.
- **An existing project migrates by itself.** At session start, `epico-migrate-dir` moves `.epic/` to `.epico/`, renames the index, rewrites the two marker pairs and the exact `.epic` entries of `.gitignore`. When git tracks the folder the move is a `git mv`, staged and never committed — review and commit it. With both folders present nothing moves and the session says so; `epico-doctor` reports a leftover `.epic/` as an error. The old markers, the old `EPIC_SUPERVISION`, `EPIC_ARCHIVE_LOCK_TIMEOUT` and `EPIC_AI_MEMORY_BIN`, and `--epic-dir` are still read. Memory pages keep their `epic/<type>/` paths, so what is already stored is still found. The managed `CLAUDE.md` block is reported stale once; `/epico:epico init --repair` rewrites it.
- The quality catalog's "Pinned Actions" becomes **Hardened workflows**: besides SHA pins, least-privilege `permissions:`, no `pull_request_target`/`workflow_run` checking out untrusted code, no `${{ github.event.* }}` inside `run:`, `persist-credentials: false`, `timeout-minutes` on every job, and a self-hosted runner only on a private repository. Proved with `zizmor` and `actionlint`.

### Added

- Catalog items **Pre-commit hook** (secrets before the commit exists), **Security policy** (`SECURITY.md`) and **Branch protection** (read from the forge with `gh api`, since it is not a file); `product` activates them without waiting for a signal. **Build provenance (SLSA)** joins the on-request tier — the one step that needs the forge's OIDC. Dependabot `cooldown` now counts as minimum dependency age.
- The repository follows them: `timeout-minutes` and `persist-credentials: false` on every CI job, and a `.pre-commit-config.yaml` running the installed `gitleaks` and `shellcheck`.

### Fixed

- The commit guard no longer reports commits that exist: it piped the whole `git log` into `grep -q` under `pipefail`, and once the history outgrew the pipe buffer the writer's SIGPIPE read as a miss — every finished group was flagged. It now matches through a here-string.
- `epico-jargon` no longer flags an explained term once the legend list outgrows the pipe buffer — the same SIGPIPE-under-`pipefail` miss, fixed the same way.

## [0.21.0] — 2026-10-19

The supervisors from `epic-supervisor` plug into the run: a claims check at validate, the project's own checks at the checkpoint, and one store for what they find.

**Minimum Claude Code:** 2.1.295, unchanged.

### Changed

- Validate runs `epic-supervise claims` after the Auditor when the command is on PATH and `EPIC_SUPERVISION` is not `off`: it compares what the run claimed with the exit codes and commits recorded elsewhere, writes `.draft/reports/claims.md` and adds each divergence to the findings store. It never blocks the verdict; without the command, one line says so.
- The checkpoint's findings step offers `epic-supervise sense --stage <N>` — the project's own checks on a fresh clone — and triages the findings store (`epic-finding list`, decisions recorded with `epic-finding decide`) alongside memory pages, deviations and open boxes.
- A proposal marked `priority: urgent` is listed first by `stories from-memory` and drafted only after its own acknowledgement; headless never drafts it.
- The supervision mailbox carries claims about a run still in progress only; everything after the run goes to the findings store, `.epic/findings/`.

## [0.20.0] — 2026-10-19

A ROADMAP stage can be closed with Epic: the plan is reconciled with what the stories delivered, the user judges before Epic does, and the next stage is detailed.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- `checkpoint <N>`: closes stage N of the project's ROADMAP in six steps — reconcile, gate, decisions and rules, findings, documents, next stage. On judgment items the evidence comes first, then the user's verdict, then Epic's reading and where the two differ; those questions carry no recommended option, and `--auto` stops before them. Documents change only through the doc writer, a finding becomes a story only there, and the `stories create --batch` command for the next stage is printed, not run. Every answer is recorded in `.epic/checkpoints/<N>.yaml`.
- `epic-checkpoint --stage <N>`: the mechanical step — each task of stage N, from a single-file ROADMAP or `docs/stages/`, as `closed`, `in-work`, `unmapped`, `mismatch` or `open`, from its checkbox and the `roadmap:` of archived and open stories; also the IDs a story names that no ROADMAP holds, and the stories with no `roadmap:`. Read-only.

## [0.19.0] — 2026-10-19

Project documents start to live: a decision reaches a document as an amendment or a superseding ADR, a story names the ROADMAP tasks it works on, the archive records which commit was validated, and sync-docs writes documents without needing memory.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- `roadmap:` in `tasks.md`: the ROADMAP task IDs a story works on, as `roadmap: [2.4.1, 2.4.2]`. Clarify asks it only when a ROADMAP or stage file numbers its tasks (never at Fast scale, in instant mode, under `--auto` or headless), and a batch from such a file adds a `Roadmap` column. `validate-story.sh` warns — never blocks — on a malformed list or an ID no ROADMAP or stage file holds.
- `epic-validated`: validate records the commit about to be audited, and whether the tree outside `.epic/` is dirty, in `.draft/validated.yaml`, right before the Auditor's spawn.
- The archive manifest entry records `roadmap` and `validated_sha` when the story has them. Both are optional, so entries written by earlier releases still read as complete.

### Changed

- sync-docs works without memory: a collector gathers memory pages when they are there, the deviations of stories archived since the last sync, and decisions named in the request; the doc writer asks "write and commit `<file>` on `<branch>`", commits only that file with `Story:`, `Finding:`, `ADR:` and `Why:` trailers, refuses a document with uncommitted edits, leaves the file uncommitted when git has no identity or a hook refuses, and never pushes.
- An ADR's text is never rewritten: a changed decision is a new ADR that supersedes it; the same decision with new detail is a dated amendment at the end, in the form the project already uses. Every new or superseding ADR carries `## Enforcement` as `- check:` or `- judgment-only:` bullets.
- The managed `CLAUDE.md` block finds root documents under `docs/` too, and lists `docs/stages/` and `OVERVIEW.md` when present. `epic-doctor` reports the block stale once in projects that keep their documents under `docs/`; `epic-claude-md write` refreshes it.

## [0.18.0] — 2026-10-17

First published as 1.1.0 the same day; renumbered, and the 1.x tags withdrawn.

Every level protects the user's data, a finished group is always committed, a layperson never meets a word without its meaning, and the model is chosen where it runs.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- `hook-legend-guard.sh` (Stop): for a `layperson` requester, a process word from any text of the turn — status lines between tool calls included — with no legend blocks the end of the turn once and asks for the legend in the closing. `tasks.md` records `requester: layperson | developer` at every scale for it; `validate-story.sh` checks the value. The commit guard now tells the model to commit silently.
- The session model is suggested, never switched: a Fast or Spike triage proposal carries a `Model` line when the session is not on Sonnet (`/model sonnet` to continue, or `claude --model sonnet` for a new session), and `instant` says it in one line before the work. Nothing is suggested under `--auto` or headless.
- The run model: clarify's last question for a Standard or Full story asks which model runs it (Sonnet recommended) and records `run-model:` in `tasks.md`. The closing names how to open a session on it (`/model` or `claude --model`), and the run start says so in one line when the session differs — informing, never blocking.
- `hook-commit-guard.sh` (Stop): a finished group whose pre-authored commit is missing blocks the end of the turn once, naming the message. Fails open with no git identity, no work tree, no stories, or on the second stop.

### Changed

- The layperson term list also covers the Epic's own internal words, in either language: `triagem`, `referências do Epic`, `modo instant`, `caixas do plano`, `run report`, `gate`, `stub`, `assertion` and a bare `/epic:epic`.
- A technical or English term may reach a layperson when the same message carries its legend (`*term* — what it means here`, in their language). `epic-jargon` passes legended terms, reports them under `explained`, and flags only the unexplained ones.
- Triage has one scale: the four modes, read from risk and uncertainty. The story-level Trivial / Simple / Moderate / High labels are gone (file counts stay as examples on each mode); the sub-task Complexity field stays, since it routes the Executor model and the tech review.
- The runtime floor gate checks the declaration where a tool reads it (`.tool-versions` for a single script with no manifest), not only the installed version.
- The data-integrity floor item also covers a wrong-shaped file (treated as corrupted), never replaces an earlier set-aside copy, and makes a failed save say so.
- Data integrity joins the security floor, so every level owes it: a file the program reads back is written through a temporary file and a rename, and a missing or corrupted one never crashes the program or gets overwritten. A program with no data file records `no persisted data` on the gate. `validate-story.sh` now names five floor items; the context-tier row keeps only the format version.

## [0.17.0] — 2026-10-17

First published as 1.0.0 the same day; renumbered, and the 1.x tags withdrawn.

The memory pool becomes typed, a story can be drafted from it, documents can be synced from it, and an outside supervisor can talk to a run — always as claims the run verifies.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- Supervisor relay: `hook-inbox.sh` claims `supervision:` messages from the project's ai-memory mailbox after every closed box (a hook) and at every group gate (`epic-inbox --story <dir>`), records them in the run report and hands them to the orchestrator as untrusted claims; `references/supervision.md` is the protocol — verify, adjust if it reproduces, reply with `epic/supervision/<NNN>/<check>-reply` either way. `EPIC_SUPERVISION=off` turns it off. Supervisors live in the separate `epic-supervisor` repository.
- `stories from-memory [<page>]`: a story drafted through CREATE from a `proposal` page, verified against the code first, with `source: memory:<page>`.
- `sync-docs`: `finding` and `decision` pages become a diff for ROADMAP, the PRD, the constitution's invariants and the ADRs — one document at a time, written only on yes; a changed ADR is a new ADR that supersedes it, never an edit.

### Changed

- `executorModel` plugin option: `inherit` (default — the session's model, as before), `haiku`, or `by-complexity` (Haiku for Trivial and Simple sub-tasks). A Haiku Executor costs about a third less and takes longer under a Sonnet session.
- The scope block declines out-of-scope requests without pressure wording; refusals and engagements unchanged.
- The parallel route stays: it runs only for a proven-independent group, finishes sooner and costs a little more; `--serial` declines it.
- Memory pages are typed: `epic/<type>/<NNN>-<slug>` (`decision`, `gotcha`, `deviation`, `finding`, `research`, `progress`, `proposal`), with `as_of`, the story and typed links (`causes`, `fixes`, `contradicts`, `supersedes`). Only technology-tagged gotchas and research go to `_global`. Paths moved: `epic/deviations/` → `epic/deviation/`, `epic/audit/` → `epic/finding/`.
- Triage also recalls `_global` gotchas and research for the detected stack, as pointers verified against the code.

## [0.16.0] — 2026-10-17

The orchestrator keeps less in its context, and the project carries its own rules: a mandatory constitution and a managed `CLAUDE.md` block.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- `epic-deviation add|list|discharge|amend`: the one writer of `.draft/deviations.yaml` — stable ids, atomic writes under a lock, a hand-written register read and a malformed line refused by number.
- `epic-report`: both Auditor verdicts and the size of every list, without the YAML; `--list <key>` for one list.
- `epic-claude-md write|check|show`: a block at the end of the project's `CLAUDE.md`, between `<!-- epic:start -->` and `<!-- epic:end -->` — constitution pointer, project docs, lookup order, the Quality commands, code rules, invariants, examples; under 100 lines, nothing outside the markers touched, `@AGENTS.md` added once. Written by `init`, refreshed by `init --repair`, flagged by `epic-doctor` when missing or stale.
- `references/lookup-order.md`: code, memory as a pointer, the installed dependency, LSP, versioned docs, issues, web.
- `init --repair`; the constitution gate in triage.
- CI: `claude plugin validate --strict` on the plugin, marketplace, skills and agents.

### Changed

- Sub-agents write their full report to `.draft/reports/` and hand back the closing block, deviation entries and at most ten lines.
- The context band is read after every task group; `degraded` stops at the group boundary with `stories NNN run all`, `--auto` included. On 1M families `efficient` ends at 400k; `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` puts every family on the 200k bands.
- The orchestrator reads files back by section (`grep`, `epic-report`, `epic-deviation list`), never a whole report.
- Executor `effort` per spawn, by sub-task complexity (`low` Trivial, `medium` Simple).
- The constitution is mandatory and complete: Defaults, Quality, Security floor, Reversibility, Runtime (isolated by default for a layperson), Invariants; tooling derived from the host, nothing installed without a yes. Triage refuses Standard and Full without it. Runtime provisioning only at `project` and `product`.
- `init` offers `permissions.deny` on `.epic/archive/**`, ignores `.claude/worktrees/`, offers `worktree.baseRef: "head"`; materialized tests are committed before a parallel spawn; the parallel route is on trial.
- The archive weight guard keeps images of at most 2 MB under `proof/`.
- The story list marks dormant drafts with the archive and supersede commands.
- `userConfig` offers `options` for `defaultScale` and `aiMemory`; README drift fixed (agent and hook counts, output-style claim, `bin/` on surfaces without a shell).
- Headless never starts the step after a mode (a `/doctor prompt-audit` finding).

## [0.15.0] — 2026-10-17

Tests stay honest under TDD, the Auditor reports claims it checked instead of trusting them, and `--auto` stops asking.

**Minimum Claude Code:** 2.1.295, unchanged.

### Added

- `epic-test-diff`: compares each materialized pre-authored test with its authored copy. `close-subtask.sh` runs it before closing a sub-task that has Red evidence: setup edits pass, a changed, removed or added assertion line refuses the close. Only a refine that carries the delta into `.draft/authored-tests/` releases it.
- `epic-jargon`: checks a layperson closing against a term list drawn from the plain register; the orchestrator rewrites until it passes.
- The Auditor checks that a bugfix's regression test fails on the commit before the fix (check 11).
- `fail-record`: an audit whose only problem is the register (an inaccurate or unrecorded deviation) lists the exact fixes in `record_issues[]`; the orchestrator applies them and treats the audit as a pass — no fix round, no second Auditor.
- The audit report carries `claims[]` (Executor-report claims, `confirmed | partial | unsupported`, with evidence), `checks_run[]` (what was run for a check that found nothing) and `not_verified[]` (the loss annotation, never omitted).
- Every run's closing has a `Not verified:` line.
- `--auto` logs every assumption it made in `.draft/run-report.md` under `## Assumptions`, and as the memory page `epic/decision/NNN-auto-assumptions.md` when memory is available.
- A bugfix report is split at triage into observed, expected, the reporter's diagnosis and the proposed fix; the last two are recorded as unverified.

### Changed

- Red counts only when the run reaches an assertion and fails there, against a stub of the API under test. An import, fixture, setup or runner failure is `setup`, not Red; `red-evidence.yaml` entries carry `red_at: assertion`.
- The Executor may repair a pre-authored test's setup (fixtures, helpers, imports, paths), never an assertion; it re-confirms Red before implementing and reports the repair as `test_surface_adjusted`.
- In Standard stories the Executor writes Unit tests first, at run time, with Red confirmed inline; the Test Advisor authors Integration and E2E only. Full is unchanged.
- The Red scratch lives under `${TMPDIR:-/tmp}/epic-red/<story>/` and is removed at the end of the spawn — never under `.epic/`.
- Three failures of the same command end a sub-task as `failed`, on the Executor and the inline route alike.
- `--auto` asks only on failure: group gates, doubts and the end-of-run step take the recommended option. The end-of-run step is started when it is Validate or Run the rest; anything else is printed as a command. A Fast story without the flag still stops on a doubt the constitution does not cover.
- The Auditor's reply is the verdict, what blocks it, what was not verified and a count of what stays in the file; Executor reports are kept in `.draft/executor-reports.md` and verified as claims. The spawn prompt states the review budget: one validation and at most two fix rounds.
- CI recipes set `--permission-mode acceptEdits` and `--permission-prompts none`, name `Edit` and `mcp__ai-memory__*` in `--allowedTools`, and check that the six sub-agents loaded. `--bare` stays forbidden: it skips the hooks and the sub-agents and accepts only an API key.

## [0.14.0] — 2026-10-13

Sub-agents report instead of being cut off, the guards hold from any directory and fail closed, and a run that stopped moving shows on disk.

**Minimum Claude Code:** 2.1.295, one floor for every feature.

### Added

- `epic-doctor`: a read-only check of `.epic/` — constitution and its `## Defaults` / `## Quality` sections, `.gitpolicy`, `EPIC.md` behind the disk, archive manifest, stories missing `tasks.md` or `story.md`, `.draft/red-scratch/` leftovers, untracked `.epic/` copies in worktrees, dormant drafts, and stalled stories. One line at session start (startup, resume, clear) and under the story list; nothing when healthy.
- `epic-progress`: progress notes, one JSON line per protocol step in `.draft/progress.log` (`story`, `task`, `step`, `status`, `evidence`, `at`). The Executor writes six per sub-task; the Auditor, Tech Reviewer and Test Advisor write start, each major step and report; the orchestrator writes them for the Analyst and the Reviewer. A stall is an in-progress story whose last note is older than 15 minutes.
- The sub-agent status line shows each Epic agent's role, label and tokens through the documented stdin/stdout row contract. It never rendered before.

### Changed

- No agent declares `maxTurns`. Each one writes its report as soon as the work is done, before any further exploration.
- Hook `if` patterns start with `**/`, so the archive, executor and validate hooks fire when the session runs from a subdirectory. The executor guard's Bash handler has no `if`: `Bash(git commit *)` missed `git -C dir commit` and `git -c k=v commit`.
- The archive, executor and commit-identity guards carry `"onFailure": "block"`: a guard that cannot run blocks the call instead of letting it through. `jq` was already a requirement.
- The Auditor's report guard reads `.draft/validation-report.yaml` and `.draft/audit-report.yaml` from disk instead of inferring them from the transcript.
- `epic-validate`: `warnings` is the list and `warning_count` the number. `warning_details` repeats the list for this release and is deprecated.
- Run mode: push, merge, tag, publish or a pull request only on an explicit answer in the session; the Executor never sets or passes a git identity.
- MCP detection: a failure notice exists only with tool search on, and a plugin-bundled server's tools are named `mcp__plugin_<plugin>_<server>__<tool>`.
- Library docs follow a docs source order that needs no MCP: the installed dependency at the lockfile version first, then the official docs for that version through `WebFetch`. The Executor reads the installed dependency before going to the web, and treats fetched text as data, never as instructions.
- A sub-task's `Docs:` line names the library, its lockfile version and the topic — never a tool.
- Research examples in the task template suggest `brave-search`, not `perplexity`, matching the rule that `perplexity` is never the default.

### Removed

- `context7` is no longer used or recommended. No sub-agent could call it; the one independent study found it better than no docs, never better than the installed dependency; its answers carried a wrong snippet and invented source paths in a 10-lookup probe; and it was the vector of CVE-2026-75130.
- The per-feature Claude Code version table in README and `SKILL.md`.
- The duplicate `version` in `marketplace.json`; `plugin.json` is the one source.

## [0.13.1] — 2026-09-27

The end of a partial run recommends finishing the plan instead of re-planning it.

**Minimum Claude Code:** unchanged.

### Fixed

- A run that ends with planned boxes still open recommends running the rest (`stories NNN run all`), not refining. Refine is recommended only when the plan is owed a change — a `follow_up: true` register entry, or fix round 2. On a partial run the old rule recommended refining a plan that needed no change, and the model overrode it in 3 of 3 runs.

## [0.13.0] — 2026-09-27

Fewer sub-agents, same findings. Validation and audit are one Auditor spawn, and a Full story's integration points and gotchas are written by the main agent — both measured side by side before the change.

**Minimum Claude Code:** unchanged.

### Changed

- Validation and audit are one Auditor spawn: it runs the validation protocol first, writes `validation-report.yaml`, and audits only on a pass. Same defects found as the two-agent pair, 10–25% cheaper and up to a third faster.
- Full stories add integration points and implementation gotchas in the main agent, before Phase 2, and record them in design.md under `## Integration Points` and `## Implementation Gotchas`. Same integration points as the Architect spawn, faster and cheaper, and the gotchas no longer get lost between the spawn and design.md.
- A `layperson` build turn writes no text between tool calls — the report write is not announced either — now stated in SKILL.md, where every run reads it.

### Fixed

- The Auditor judges scope creep on a story anchored on the repository's root commit against the files its sub-tasks name: that commit carries the scaffold too, and every scaffold file used to read as scope creep.

### Removed

- The Validator and Architect agents. `agents/validator.md` became `references/validation-protocol.md`, which the Auditor runs as Part 1.

## [0.12.0] — 2026-09-27

The end of a run offers one next step, decided by the story's state, and archive follows a passing validate. The context bands follow the model in the transcript, the fix loop is bounded, and the sub-agent audit fixes land.

**Minimum Claude Code:** unchanged.

### Changed

- The end-of-run question reads the context `band` that `epic-telemetry` derives from the model in the transcript — Haiku: highly efficient up to 100k, efficient up to 150k; Sonnet, Opus and Fable: up to 200k and 500k. Above that, validate and refine are replaced by the command for a new session. `--window` is now an optional override.
- The validate → fix → revalidate loop is bounded: each round's cost is stated, a revalidation after a fix round is asked, never chained, and step 6 offers no third round unless the user asks for it.
- Language: the chat is entirely in the user's language, option labels and the recommended marker included; code and comments are English, with a translated comment added below the English one only on request. Every agent states which of its outputs are English.
- A sub-task with no ToDo and no runnable Validation is `failed` before routing — nothing is changed and nobody invents its scope.
- The Auditor fails a story only on gaps, unmet gates, inaccurate deviations and missing Red. Scope creep is judged against what the story's own commits added, and both it and code-review findings are advisory.
- The Validator fails a `[x]` sub-task with no runnable Validation command (it used to SKIP it), and runs each command with a timeout and closed stdin.
- The Executor spawn prompt now carries the sub-task's Context, Acceptance and the group's `Commit:` message; the Executor reports deviations instead of writing `.draft/deviations.yaml`, and `failed` carries a `reason`.
- The Tech Reviewer covers the single-technology review of a `High` sub-task and reports `INCOMPLETE` instead of a pass it could not finish.
- The end-of-run question offers one next step instead of a menu: refine when work is pending (an open box, a register entry with `follow_up: true`, or fix round 2), validate otherwise, plus *Stop here*. It is asked with `AskUserQuestion` whenever the tool is callable, `--auto` included; the recommendation is written as text only when the tool is not available.
- The Executor and the Auditor run at effort `high` instead of `max`. Measured side by side, `max` found no planted defect `high` missed and wrote the same passing tests, at two to four times the cost and wall clock.
- The completeness checklist is written by the main agent instead of an Analyst spawn: the same questions, in about two thirds of the time. The Analyst now only scans the codebase at triage.
- Archive follows validation. Run mode no longer offers it, and `archive-story.sh` archives without `--force <reason>` only a story reading `validated` with no open box. A story reading `done` or `superseded` is refused by name. Supersede's archive offer passes `--force "superseded by MMM"`, and the question names the flag before the user accepts.

### Removed

- The Fork Route. The model never chose it, and when forced it tied inline on large sub-tasks and lost on small ones.
- `memory: project` on the Analyst and the Auditor, and init's offer to ignore `.claude/agent-memory/`. Project memory is ai-memory, written by the orchestrator; a leftover `.claude/agent-memory/epic-*/` directory can be deleted.

## [0.11.1] — 2026-09-27

The routing table now says what the runs already did: a sub-task names its files anywhere in its body, and tech review follows the work on every route.

**Minimum Claude Code:** unchanged.

### Fixed

- Routing: a closed-spec sub-task may name its files in the title, the Objective or the ToDo, not only the ToDo. Tech review now applies on the inline route too, and a `High` complexity sub-task is reviewed even when it uses one technology.

## [0.11.0] — 2026-09-26

A finished run now asks what comes next — validate, refine or archive — and fits the answer to how much of the session is left. A run never signs a commit with an identity it made up.

**Minimum Claude Code:** unchanged.

### Changed

- A finished run ends with one `AskUserQuestion` — validate, refine or archive — instead of a `y/n` Validator prompt. Validate and refine are recommended in the same session below 50% of the context window, allowed up to 75%, and above that replaced by the command to run in a new session. Archive is offered only on a story that just reached `done` with nothing deferred. A headless run logs the recommendation and starts nothing. A layperson is also offered to see the program running before the other options.

### Added

- A PreToolUse guard denies a commit that supplies its own identity (`git -c user.*`, `--author`, `GIT_AUTHOR_*`) and any `git config user.*` write. With no identity configured, a run makes no commit and tells the user how to set one.
- `epic-telemetry --window <tokens>` reports `context.used_pct`, the fill of the orchestrator's context window, read from the last main-thread message of the transcript.

### Fixed

- The quality catalog's format check names the project's files instead of `.`, so `prettier --check` no longer reads `.epic/` and fails on the run report written after the gate closed.

## [0.10.0] — 2026-09-26

The plugin now follows the Claude Code documentation and uses the platform's own features before its own machinery. Development history is gone from every shipped file.

**Minimum Claude Code:** unchanged. The eval suite needs `claude plugin eval` (v2.1.269+) to run; the plugin itself does not.

### Added

- `bin/epic-*` wrappers for every script a reference runs, called by bare name from the Bash PATH.
- A SubagentStop guard keeps the Validator and the Auditor running until they have written their report file.
- A PreToolUse guard stops the Executor from running `git commit` or editing `tasks.md`.
- A headless run (no `AskUserQuestion`) answers its own gates with the recommended option, records each as an assumption, and runs the mode to its end.
- Plugin options reach the skill through `${user_config.*}`, with each default written beside it for an option never saved.
- An eval suite for `claude plugin eval`: 30 trigger cases and 6 end-to-end cases, run in an isolated home.
- A provenance lint over skills, agents, references, scripts and tests.

### Changed

- `SKILL.md` stays under the post-compaction budget, with the standing rules (Language, Validation, Gotchas) first; Instant and Output Rules moved to their own references.
- "Can someone answer?" is decided by whether `AskUserQuestion` is available; the Task tools are optional progress display.
- Sub-agents are awaited whether they run in the foreground or the background; spawn prompts carry only inputs and defer to each agent's definition.
- Parallel Executors run with `isolation: "worktree"`, after a check that `worktree.baseRef` is `head`.
- The stale-story check runs in `/epic:epic stories` instead of a background monitor.
- MCP availability is read from the tool list; no probe call is made.
- One SessionStart(compact) hook renders the active story from disk after a compaction, under the 10,000-character hook limit.
- `init` recommends the built-in `/init` for `CLAUDE.md` and offers `permissions.deny` rules for protected files.
- Story artifacts under `.epic/` are always English; this is not configurable.
- The engineering level is asked when the request does not settle it; `tool` is taken only when nobody can answer.
- List annotations are neutral values rendered in the requester's language.
- CI recipes load the plugin with `--plugin-dir`, select `system/init` by type, and bound each run with `--max-budget-usd`.
- `story-telemetry.sh` reads sub-agent transcripts; the README points to OpenTelemetry, `/usage` and the `-p` JSON result first.

### Removed

- Teams mode, its hooks and the `teams` subcommand. Agent teams are a native, interactive-only feature.
- The `artifactLanguage`, `enableStaleMonitor` and `staleCheckIntervalSeconds` options.
- The commit-defer, PermissionDenied, CwdChanged, FileChanged, PostToolUseFailure, PreCompact and UserPromptSubmit hooks.
- `run-evals.sh` and `trigger-detect.sh`.

### Fixed

- The PostToolUse validator's errors now reach Claude as hook context.
- The orphan-draft notice after `/clear` is shown, with one removal line per draft instead of a glob.
- The `!` project-state lines resolve from the project root and tell "no commits yet" from "not a git repo".

## [0.9.0] — 2026-09-24

One through-line: **the plugin now carries only what the run in front of it
needs.** `SKILL.md` went from 56 KB to 22 KB and the run mode from 86 KB to 65 KB;
the protocols load where their mode reaches them. The interface a requester reads
is asked in their language instead of inherited from the artifacts' English, and
the security floor is checked instead of requested.

**Minimum Claude Code:** unchanged from 0.2.0. Every measurement behind this
release ran on Claude Code 2.1.281, which by itself cut the cost of the same
Epic commit to about a quarter of what 2.1.278 charged; numbers from before
that version are not comparable with these.

**Triage variance** (the release monitor, five runs of the beginner's request on
this commit): scale **Fast 5/5**; engineering level `experiment` 4, `tool` 1.
Taken on the host rather than through `triage-variance.sh`, whose image carries
Claude Code 2.1.269 and Node 20 — a sample there would not measure this version.

### Added

- **The security floor is verified instead of requested.** `validate-story.sh`
  now reports, as an error, every floor item — supported and declared runtime,
  secrets, README, dependency vulnerabilities (SCA) — that carries no gate in
  the Quality Gates section of `tasks.md`. Until now the whole chain was prose:
  the legend names the item, `tasks.md` generates a `Qn` gate per legend line,
  Validate settles the gate by running its command. Nothing checked that the
  first link was ever written, so a story whose legend omitted the floor
  produced no gate, gave Validate nothing to run, and passed. Measured
  2026-09-19: four of fourteen Epic arms in the seven-language matrix skipped
  floor items and all four validated clean. The check matches the item's name
  rather than a command, since the command is the project's own, and is gated
  on a declared `engineering:` level — fail-open on absence, so every story
  written before 0.7.0 validates byte-identically.
- **The interface language is asked, not inherited.** The English rule covers
  the artifacts, the EARS keywords and the code identifiers; it never covered
  the menu, the prompts, the error messages and the README the requester's own
  users read, and nothing said where it stopped. A request written in another
  language now gets one clarify question, in that language — English, the
  language you wrote in, another — skipped when the request is already in
  English. Where no round runs (`instant`, or a spent budget) the default is the
  language of the request, stated on its line. Measured 2026-09-21: given the
  same Portuguese request, `instant` shipped an English menu "on the
  repository's standing rule that written artifacts are English" and the
  requester spent a turn undoing it, while the un-shortcut run asked and got it
  right the first time.
- **Every line the requester can see is in their language, including the
  notes between tool calls.** The Language rule said communication follows the
  user's language; it did not say a status line is communication. In three
  Portuguese runs, two or three lines per run — "Now closing the final checks",
  "The piped input dropped lines" — arrived in English between tool calls.

### Changed

- **The skill carries its router, not every protocol.** Loading the skill put
  the whole `SKILL.md` — 56 KB, about 22,000 tokens — into every run, and a
  run re-reads its context at every step: that text was a quarter to two fifths
  of all the context a Create or Instant run re-read. The triage, clarify,
  personas, phase-execution and lifecycle-status protocols now live in
  references of those names, each loaded where its mode reaches it; a stub with
  the same heading stays in `SKILL.md` and points on. Instant, which asks
  nothing, never loads the clarify protocol. `SKILL.md` went from 56 KB to 22 KB.
  The core keeps one load it cannot leave to a link: the requester's register.
  A first cut left `plain-register.md` reachable only from inside `triage.md`,
  and two of five beginner runs never opened it and shipped with no test.
- **One source for the Executor protocol.** `run-mode.md`'s prompt template
  recited the six steps, the report format, the closing block and the
  prohibitions that `agents/executor.md` already carries, and the two copies had
  drifted — each held rules the other lacked. The template now carries the
  sub-task's fields and defers the protocol to the agent definition.
- **`run-mode.md` loads its optional machinery on demand.** Parallel Execution,
  Multi-Tech Review and Agent Teams moved to files a run opens when it needs
  them (`run-parallel.md`, `run-tech-review.md`, `teams-mode.md`); the mode file
  keeps a pointer with the trigger. With the deduplication above, the file a run
  always reads went from 86 KB to 65 KB.
- **The instruction files no longer carry the sessions that produced them.**
  Measurement narrative, requester quotes and one description of a ceiling
  removed in 0.7.0 left `engineering-level.md`, `plain-register.md`,
  `run-mode.md` and `self-review-checklist.md`. Every rule and every number
  stays; how it was obtained belongs to these notes.

### Fixed

- **The runtime declaration is named for every stack.** The security floor's
  runtime item told Node, Go and Python where to declare their version and
  left Rust, Ruby and PHP to guess: one Rust run declared its `edition`, which
  is a language dialect and not a minimum compiler, and one PHP run named the
  version only in its README. The row now names `rust-version`, the Gemfile or
  `.ruby-version`, and `require.php`. The `instant` section also still counted
  three floor items after the README became the fourth.

## [0.8.0] — 2026-09-19

One through-line: **a level decides how much engineering a story buys, never how
much safety** — and the cheapest way to say "this one is disposable" should not
cost a conversation. Everything here was settled by running the plugin rather
than by reasoning about it: a six-run relay series with the owner answering every
question, a 7×3 matrix over JavaScript, TypeScript, Ruby, Python, PHP, Go and
Rust, a four-arm fork probe, and 38 generated applications executed against the
one requirement they were all given. See
[`.epic/docs/session-2026-09-19-instant-floor-and-matrix.md`](.epic/docs/session-2026-09-19-instant-floor-and-matrix.md).

### Added

- **`/epic:epic instant <description>` — the disposable-work shortcut.** Three
  pins and no new state: `scale: fast`, `engineering: experiment`, and a quality
  legend holding the security floor alone. The technical question round does not
  run, because typing `instant` already answers the first question of the intent
  cascade. No artifact carries the value `instant` — it is an entrance, not a
  state, so validation, the index and the telemetry read such a story exactly as
  they read any other. When the request is plainly larger than the shortcut, the
  Epic says so in one line and proceeds anyway: the requester chose the level,
  and a shortcut that argues is a shortcut nobody uses.
  ([`SKILL.md`](skills/epic/SKILL.md#instant--the-disposable-work-shortcut))
- **The security floor — three items no level drops.** Until now `experiment`
  activated *nothing* and its legend read `none`. A throwaway is thrown away;
  the machine it ran on is not, and neither is the account whose token it
  carried. The floor is **supported and declared runtime**, **secrets** and
  **dependency CVEs** — one command each, no configuration file, seconds to run.
  A floor that cost minutes would be argued with; this one is cheaper than the
  argument. ([`quality-catalog.md`](references/quality-catalog.md))
- **The runtime item now carries the clean-version rule.** Prefer the LTS; take
  the current widely-used stable instead **when the LTS is the one carrying a
  known vulnerability**. A hello world on an end-of-life interpreter is
  vulnerable before its first line, because the environment is the hole.

### Changed

- **The four engineering levels are restated in the requester's own
  vocabulary**, and the level is fished for as a **cascade inside the
  orientation round**, stopping at the first answer that settles it. Intent
  rounds do not count against the question budget; technical rounds do. The
  cascade stops when a round changes neither the level nor the range of
  technology still open, and where ambiguity survives that, a free-text answer
  is asked for rather than another menu. `experiment` stops meaning "disposable"
  — the artifact may well go on being used exactly as it is; what does not exist
  is any intention to maintain it.
- **The floor is `fast`, and it rises only when an answer pushes it — and it may
  come back down.** Going down is cheap; going up after the work has been paid
  for is not. Triage no longer assumes `tool` when the request does not settle
  the level: measured 2026-09-18, that default put a beginner's throwaway CRUD
  at 9.4× its control in wall clock and 14.5× in cost, where `tool` promises
  2–3×. ([`engineering-level.md`](references/engineering-level.md))
- **The per-level box ceiling is gone; the bound moved to the unit.** A sub-task
  is one Executor pass with a `Validation:` command that proves it alone — which
  is the limit a work breakdown structure actually applies (size of the work
  package, never the count). The plan keeps its single threshold in bytes.
  ([`tasks.md`](references/tasks.md#authoring-ceiling))
- **The Architect reasons over the Analyst's scan instead of repeating it.**
  Four of its five original tasks were already answered by the block its own
  prompt injects verbatim; only the gotcha hunt was ever unique to the persona,
  and integration points are re-scoped rather than duplicated — the Analyst
  answers them against the raw request, the Architect against `story.md`.
  ([`architect.md`](agents/architect.md))
- **The Fork Route carries its measured economics.** Ten trivial independent
  sub-tasks, Claude Code 2.1.277: inline finished in 10.9 s for $0.071, ten
  forks in 20.7 s for $0.319, ten `general-purpose` sub-agents in 21.2 s for
  $0.470. Spawn overhead dominates when the unit is small, and a sub-task here
  is small by construction. Take the route only when each sub-task is large
  enough for overlap to repay the spawn, and record the reason.

### Fixed

- **`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is documented correctly at last.**
  It is **not a fork setting** and is required on every run, fork or no fork:
  under `-p`, sub-agents are backgrounded *by default with fork mode off* — ten
  `general-purpose` spawns with `CLAUDE_CODE_FORK_SUBAGENT=0` all reported
  `is_backgrounded: true`. A backgrounded sub-agent's result arrives only as a
  completion notification in a later turn, which is the failure story 026 fixed,
  and it reaches the Analyst, the Validator and the Auditor as much as any fork.
  With the variable set, ten forks all reported `is_backgrounded: false`. The
  previous text claimed the opposite on the strength of a single unrepeated
  probe. ([`run-mode.md`](references/run-mode.md))

### Measured

The numbers this release is calibrated against, so the next one can contradict
them with newer ones rather than with taste.

- **A `fast · experiment` story costs about 8.4× its control**, across seven
  languages in a tight range ($4.91–$6.60 against controls of $0.43–$1.01) —
  where the level promises 1× and the owner's rule allows 5. What the multiple
  buys is measured too: modular structure in 5 of 7 against **0 of 7** for the
  control, README 6 of 7 against **0 of 7**, secrets scanning 6 of 7 against
  **0 of 7**. The promise is what needs recalibrating, not the spend.
- **The scale moves the bill further than the level does.** Same requester, same
  request, same `experiment` level: `standard` cost 10.9× its control, `fast`
  cost 4.3×. The level had been asked about and answered; the scale was never
  mentioned in the whole conversation. That is what the proposal line and
  `scale_reason:` now address.
- **The intent sentence resolves the level without a question.** "This is just a
  test — I am not going to update it or maintain it" produced `fast ·
  experiment` in **14 of 14** Epic arms, in seven languages, with no level
  question asked anywhere.
- **Re-exploration is 4% of an Executor's time** (write 40%, Bash 56%, over 59.3
  minutes of measured steps). Any shared-context mechanism between sub-agents is
  bidding for those four points.
- **Fork loses to inline on both axes** at this plugin's unit size: ten trivial
  sub-tasks ran inline in 10.9 s for $0.071, as ten forks in 20.7 s for $0.319.
- **No generated application destroyed user data.** 26 of 26 executable
  applications preserved a corrupt collection file seeded at the path their own
  source declares — control and Epic alike.
- **The floor is not yet enforced.** Four of fourteen Epic arms skipped at least
  one floor item; one skipped three. The floor is prose in a catalog and nothing
  checks that it ran. Making each item close with recorded evidence is the first
  item of the next release.
- **The noise floor is ~1.8×.** Re-running one stack on the same commit moved its
  Epic arm from $8.94 to $5.65. No claim under 2× is defensible at n=1.

## [0.7.0] — 2026-09-17

Seven commits on the 0.7.0 branch, one through-line: **who is asking, how the
Epic asks, and what it verifies** — then, measured on the branch's own first
runs, what that costs. The requester is a four-field block and the level never
changes the scale; Clarify asks the way an architect asks a client, with a
budget counted in questions; a quality catalog gives the story a legend and
generates its gates; Fast runs `--auto`, the orchestrator's effort is the
session's, memory names a permitted provider; every sub-agent runs in the
foreground; a request for speed changes the words, not the steps; and an
engineering level — how long the thing must last — decides the catalog tier,
the shape of Phase 3 and the plan's ceiling. Two of the seven are fixes of
defects measured on this branch's first runs, and the entries below carry the
numbers.

**Measured on the release commit — the beginner's request, persona harness,
2026-09-17.** Control: 2 min, US$ 0.62, one file, no tests. Epic: Standard ·
`layperson` · `tool`, a plan of 12 Task List boxes (the `tool` ceiling
exactly), 7 questions of a budget of 9, one sub-agent (the Analyst, in the
foreground, one user turn), delivered `done` in **23 min and US$ 11.88** — 5
commits, 4 source and 4 test files, 39 green tests, `engines.node: ">=22"`
declared with the image's Node 20 flagged as out of support, an atomic write
with a backup of a corrupt file, a formatter, a linter, a JSDoc type check, an
`.editorconfig` and a README; the persona ended with "ta funcionando mano,
ficou top". **Against the owner's rule — up to 5× is justifiable — it is a miss:**
11× the control's clock and 19× its cost, where `tool` is supposed to cost
2–3×, and the run's own
report names the always-tier toolchain as the largest cost. That is the
calibration the level file promised to take: what `tool` activates, and the
multiples, are what the next round recalibrates. One defect in the
deliverable, invisible to the run: `npm test` is `node --test test/`, which
passes on Node 20 and fails on the Node 22+ the package declares — the
directory argument changed meaning — which is what a harness image with a
supported runtime would have caught.

**Triage variance (n=5, same request, release commit):** Standard 3, Fast 2. The engineering level read `tool` four times and `experiment` once, on one of the Fast samples; 305–708 s and 0.5–1.7M input tokens per sample. The request that drew Fast once and Standard twice on 0.5.0 still draws both, and the level moves with the scale. A monitor, never a gate.

**Minimum Claude Code:** unchanged from 0.2.0. Everything in this release is
prose the orchestrator follows, scripts and tests; nothing in the runtime
moved.

### Added

- **An engineering level — how long it must last decides how much the story
  pays for** (new `references/engineering-level.md`; `skills/epic/SKILL.md`
  Adaptive Modes, Triage, Clarify, Phase Execution, Draft Saving, Output
  Rules; `references/requirements.md`, `references/plain-register.md`,
  `references/self-review-checklist.md`, README). Measured on 2026-09-17: two
  Standard runs for a developer's Pokédex CLI planned 43 and 47 boxes, spent
  about 25 minutes in Phase 3 while the Test Advisor wrote 22 tests before any
  code, and were stopped at 42 minutes with 28 and 2 boxes closed — the Epic
  plans every request as a product, because nobody asks how long the thing
  must last. Four levels now do: `experiment` (disposable, 1×), `tool` (kept
  and fixed when it breaks, 2–3×), `project` (maintained, others depend on it,
  4–6×), `product` (may be published or sold, 8×+). Triage reads the level
  from the request's own words, takes `tool` when the request does not settle
  it, and proposes it in one line with its multiple, in the register's words,
  so the triage gate confirms it without spending a question; when triage was
  unsure, the orientation round fishes for it with the indirect questions
  ("a month from now, will you open this again?", "when it breaks, do you fix
  it or redo it?", "will anyone besides you run it?", "could it be published
  or sold?"), asked as consequences and never as a choice of level. It is
  recorded as `engineering:` in every artifact's frontmatter (`tasks.md`
  authoritative, an invented value a validation error, absence legal and
  silent), in `meta.yaml` beside the `requester` block, and in **the recorded
  line** that opens the execution plan and the end-of-run report — scale,
  requester level, engineering level with its multiple, plan size in Task List
  boxes — which is what the persona harness compares against the control. The
  multiples are against the control and are the first calibration, recalibrated
  at every release; the owner's rule — up to 5× the control is justifiable, above it
  something is wrong or unnecessary — is written down beside them. The
  level never changes the scale, the requester level, the artifacts, the gates
  or the Executor's six steps. Pinned by `tests/engineering-level.bats`.

- **The catalog names what eleven attempts lacked**
  (`references/quality-catalog.md`). Audited on eleven attempts at one
  beginner's request (15–17 September 2026): none installed a package, all
  ran on the Node 20 the image offered — out of support since April 2026 —
  none declared a version, and none carried a formatter, a linter, a type
  checker or an `.editorconfig`; an atomic write appeared only in the two
  0.5.0 Standard runs, by the model's own initiative. The always tier gains
  **a supported and declared runtime** (`engines`, the `go` directive,
  `requires-python`, `.tool-versions`) and **dependencies justified and
  current**; the context tier gains **atomic write**, with the signal that
  the program writes a file it reads back; and a syntax check (`node --check`,
  `py_compile`, `bash -n`) named as Lint now counts the item as omitted, not
  covered. **The level bounds the set**: `experiment` activates nothing and
  its legend reads `none`, `tool` the always tier, `project` adds the context
  items whose signal is present, `product` adds the CI-shaped ones without
  waiting for a signal and the on-request tier when named.

- **A quality catalog, a legend in the story, and gates generated from it**
  (new `references/quality-catalog.md`; `references/requirements.md`,
  `references/tasks.md`, `references/init-mode.md`,
  `references/constitution.md`, `references/phase-gates.md`,
  `references/validate-mode.md`, `references/plain-register.md`,
  `agents/analyst.md`, `scripts/cross-reference.sh`). The Quality Gates
  section was a fixed list of five items that named neither formatting, lint,
  types, dependency vulnerabilities, secrets nor a README, and chose nothing
  by context. The catalog has three tiers — **always** (formatting, lint,
  types, error handling, unit tests, lockfile and frozen install, dependency
  vulnerabilities, secrets, README, `.gitignore` and `.editorconfig`), **by
  context** with the signal that activates each (integration and E2E,
  contract tests, structured logs and health, migrations, SAST, image
  digest/non-root/scan, pinned Actions, accessibility, licence/SBOM/signing,
  minimum dependency age) and **on request** (fuzzing, benchmarks, coverage
  threshold, mutation). Init writes the project's default legend as a
  `## Quality` block in the constitution; the Analyst reports which context
  signals the tree carries; a story carries `## Quality Requirements` — one
  line per active item, `Qn`, with the command that proves it (a Fast story
  carries it at the top of `tasks.md`); a sub-task cites the lines it
  exercised in a `Quality:` field; the Quality Gates section gains one
  generated box per line, after the five fixed ones, settled by running its
  command; a layperson sees "the checks I ran", never an identifier.
  Activating an item never installs a tool. **`cross-reference.sh` measures
  the legend's coverage**: a `quality` object with `declared`, `cited`,
  `orphans` and `phantoms`, emitted only when a `Qn` is declared or cited,
  and either list non-empty is an issue (exit 1); four cases pin it.

- **`RELEASING.md` — what a version cut actually involves, and the traps in
  it.** Written from the 0.5.0 and 0.6.0 cuts; every step in it has been
  executed. It names the four version sites that must agree, the CHANGELOG
  link-block repoint, the merge-commit convention this repository uses, and
  the annotated tag on the merge commit. Two traps are stated rather than left
  to be rediscovered: **`bats` must run as a normal user**, because 14 cases
  make a file unreadable and require a refusal that root cannot trigger (11 in
  `archive-story.bats`, 3 in `epic-index.bats`) — which is why `act -j bats` is
  not the faithful run — and **`Analyze`/`CodeQL` have no local equivalent**,
  the one part of a release that cannot be verified before the push.
  - It also fixes the release step the plan asked for and the repository had
    nowhere to put: **take a triage-variance sample and record the
    distribution in the release's CHANGELOG entry.** Scale instability — the
    same request drawing Fast once and Standard twice on v0.5.0 — is invisible
    to the test suite, because it is a property of a model's judgement rather
    than of a script. It is a **monitor, never a gate**: one run that disagrees
    is information, and a gate of that shape was already measured flapping
    0/30 then 5/5 against a tree with no edit at all.

- **`story-telemetry.sh` reads both sub-agent markers.** The two stream shapes
  differ and only one was handled: an interactive session transcript carries
  `isSidechain` on every assistant event, while a `claude -p` stream has no
  `isSidechain` at all and marks a child with a non-null `parent_tool_use_id`
  (measured: 135 of 358 assistant events in one `-p` run). Reading only the
  first attributed every sub-agent token to the orchestrator, silently, on
  exactly the runs where delegation is what you are trying to measure. Both are
  now read, and a case pins the `-p` shape.

- **`scripts/story-telemetry.sh` — what a story cost, without mining a
  transcript by hand.** Reads a session transcript and reports tokens and wall
  clock as one JSON object on stdout, split orchestrator vs sub-agent, with an
  optional `--since` / `--until` window for a single phase. Writes no files and
  makes no network call.
  - **Tokens, never dollars.** The transcript carries `message.usage` and no
    price; a price table shipped inside the plugin would age into a confident
    wrong answer. The reader knows the current prices.
  - **Summed per distinct `message.id`.** The transcript writes one event per
    content block and repeats the same usage on each — measured at 462 events
    for 190 messages, a 2.4x inflation. `events` and `unique_messages` are both
    emitted so the deduplication is visible rather than promised.
  - **`subagent_split_verified`** is `false` until a run actually saw an
    `isSidechain` event, so a zeroed `subagent` block reads as *none seen*
    rather than *confirmed none*. No transcript available when this was written
    had run a sub-agent, and the field says so instead of implying otherwise.
  - A malformed trailing line is skipped rather than fatal: a live session's
    transcript is being written while you read it.
  - This is the on-demand half of the planned cost telemetry. The other half —
    writing the figures into the story and surfacing them in `epic-index` —
    was **deliberately not built**: it would put the plugin back to writing
    files into the user's repository, which 0.6.0 had just stopped doing.

### Changed

- **The plan ceiling is per engineering level, counted on the Task List**
  (`references/tasks.md` Authoring Ceiling, `scripts/validate-story.sh`,
  `tests/authoring-ceiling.bats`). The single 60-box ceiling let the 43- and
  47-box plans through without a word. The box arm is now `experiment` 5,
  `tool` 12, `project` 24, `product` 40 Task List boxes — the measured pace is
  about one box per minute, so the plan is where the multiple is decided — and
  a story that declares no level keeps 60, so a story written before the field
  validates as it did. Only the Task List is counted: the Quality Gates section
  grows with the legend and not with the work, and the five fixed gates alone
  would fill an `experiment`; a box inside a code fence is documentation. The
  warning names the level and cites the threshold's one home, and the offer at
  Phase 3 has three ways out — cut the scope, split into waves, or go down a
  level, which regenerates the plan with fewer quality items. Bytes keep their
  32 KB arm at every level. Five cases pin the validator: each level silent at
  its ceiling and warning one over, gates and fences not counted, an invented
  level an error naming the four, no level keeping 60, `tasks.md` winning over
  `story.md` and `story.md` read when `tasks.md` is silent.

- **Phase 3 is proportional to the level** (`references/phase-gates.md`,
  `references/run-mode.md`, `references/refine-mode.md`,
  `references/validate-mode.md`, `references/batch-create.md`,
  `agents/auditor.md`, `agents/test-advisor.md`). The Test Advisor authoring
  every test before any code cost about 25 minutes in each of the two
  developer runs. At `experiment` or `tool` a Standard or Full story now
  decides its `Tests` field inline with the Lite checklist and writes the test
  at run time — Red before Green, the same cycle Fast and spike already use —
  with no Test Advisor, no `.draft/authored-tests/` and no `red-evidence.yaml`;
  at `experiment` the field is optional, as in a spike. `project` and `product`
  keep the full Phase 3. Every consumer that read "Standard/Full" as "has a
  pre-authored test" now reads it through the level: materialization and its
  converse guard, the run-time ordering and both routes, Refine's Red evidence
  for added sub-tasks, the Auditor's Red-precedence check and batch create
  apply at `project` and `product` and are exempt below.

- **The requester is a four-field block, and the level never changes the
  scale** (`skills/epic/SKILL.md`, `references/plain-register.md`, new
  `references/developer-register.md`). Triage records `requester.level`
  (`layperson` | `developer`, developer when unsure), `requester.persona`
  (one line ending with the evidence the reading rests on), and
  `requester.always` / `requester.never`, seeded from the level's register and
  extended from Clarify answers — "I don't know how to run a command" becomes
  a `never`. The level changes the register, the question budget, the defaults
  taken silently and the shape of a gate, and nothing else. **The 0.6.0 rule
  that held a layperson at Fast is retired**: it came from one trivial request,
  and everything that had made Standard hurt a beginner — out-of-reach
  questions, document reviews, 23k-character turns — is closed by the register,
  the budget and the defaults. A beginner who asks for something Full-shaped is
  owed Full, with its gates in one line. The plain register gains the positive
  rule it lacked — explain by one example or analogy per new concept — and the
  developer register is new: direct, with context and an example on every
  option, never the basics, and honest that nothing about it is measured yet.

- **Clarify asks the way an architect asks a client** (`skills/epic/SKILL.md`,
  `agents/analyst.md`, `references/context-discovery.md`). The requester came
  to have something built, not to give instructions: they know what it is and
  what it must do, and the how is not settled in their head. So every question
  is about what and what for, and the how is proposed, never asked. Round 0 is
  orientation — up to three context questions, or one open question in the
  requester's words, skipped when the request already answers them. Every
  question asks the **consequence** the requester can observe, never the
  mechanism ("what happens to the data when the program closes?", not "JSON or
  SQLite?"). Every option carries its context and one example, plus an analogy
  for a layperson and the term for a developer. A technical decision arrives as
  options with the recommended one first, labelled, with its reason in one
  line. Rounds are free in size — the fixed 3–7 bundle is gone — and bundle
  only questions whose answers cannot change each other; a question that can
  prune another goes alone and first. **The budget is counted in questions,
  not rounds**: layperson Fast 3 / Standard 9 / Full 12, developer Fast 4 /
  Standard 10 / Full 14, the orientation round and each gate counting one.
  Measured on the format's own trial, a Standard-shaped request: nine. The
  Analyst's checklist phrases its assertions as consequences, and its items
  are asked in rounds rather than as one numbered list, which stays as the
  headless fallback.

- **Fast runs `--auto` by default, and `--step` asks for its stops back**
  (`references/run-mode.md`, `README.md`). A Fast story is small enough to see
  whole at the end, and its per-group gate was one round of the question
  budget spent on "go on". It now stops on a validation or test failure and on
  a doubt the constitution defaults do not cover, and nowhere else; `--step`
  restores the gate after every group. Standard and Full keep their gates and
  `--auto` as an explicit choice. For a layperson, a stop per group is
  promised only under `--step` — a promise about cadence is kept literally or
  not made.

- **The orchestrator's effort is the session's** (`skills/epic/SKILL.md`).
  The skill frontmatter no longer pins `effort: max` on the orchestrator: the
  session's setting applies, and a fork inherits the same. Two reasons. The
  measured Standard spent 49% of its clock in the orchestrator writing and
  thinking between calls, which is where maximum effort weighs; and the
  persona harness's control arm runs at the session default while the Epic
  arm ran at max, a confound in every comparison made so far. The agents keep
  their own `effort` fields, pinned by `tests/agent-effort-policy.bats`.
  Unmeasured as of this entry — the 0.7.0 runs are the measurement.

- **The memory recommendation names a permitted provider**
  (`references/mcp-integration.md`). ai-memory's LLM work — consolidation and
  lint — needs a provider Anthropic's terms allow for a third-party tool: an
  API key with a Haiku-class model, or a local model through an
  OpenAI-compatible endpoint. Never a Claude subscription OAuth token: since
  February 2026 OAuth from the Free, Pro and Max plans is for Claude Code and
  Claude.ai only, and ai-memory's own documentation warns that its
  `anthropic-oauth` provider risks the account. The Epic's own reads and
  writes need no LLM on the server.

### Fixed

- **Every sub-agent runs in the foreground** (`skills/epic/SKILL.md` Personas,
  and every spawn site: `context-discovery.md`, `phase-gates.md`,
  `run-mode.md`, `validate-mode.md`). Measured on the first 0.7.0 runs
  (2026-09-17): the orchestrator spawned the Analyst and the Test Advisor with
  `run_in_background: true`, ended its turn to "call back when it returns",
  and every reply became a user turn spent waiting. The beginner's Standard
  run — her first Standard, now that the level no longer holds her at Fast —
  burned 12 of 12 user turns on "ainda tá fazendo?", wrote no code and cost
  US$ 7.04; the developer's Go run did the same for ten turns. The rule: the
  orchestrator's next step is the sub-agent's result, so the call is made
  with `run_in_background: false`; a parallel Executor group is several
  foreground calls in one message, joined before the next step. Pinned by
  `tests/run-defaults.bats` D6, which also fails on any spawn site asking for
  the background.

- **A request for speed changes the words, not the steps; a downgrade is a
  question** (`references/developer-register.md`, `skills/epic/SKILL.md`).
  Measured on the developer's JS run (2026-09-17): after "pode ir direto pro
  código", the orchestrator announced a Standard-to-Fast downgrade instead of
  proposing it, then wrote tests and implementation in one batch "because
  seventeen red/green cycles would be too many turns", and closed no box —
  33 open, 18 files, 69 green tests, zero `close-subtask.sh` calls. The
  beginner asked to skip the same step and was refused; the developer
  register lacked the sentence. Now it has it — speed is fewer words and no
  waiting, never fewer steps — and the downgrade rule says the proposal is a
  one-line gate whose answer alone changes the mode. Pinned by
  `tests/requester-register.bats` Q18.

## [0.6.0] — 2026-09-16

Seven commits, one through-line: **measure, then move.** A 59-minute Standard
run was decomposed first — 49% of the clock inside sub-agents, 49% in the
orchestrator, 1.9% doing the work — and a persona simulation of one beginner
was run three times against the same request. Every change below answers a
number from one of the two. Execution routes per sub-task and no longer
delegates a closed spec; a proven parallel group runs without asking; Full is
opt-in on an architectural signal; triage reads who is asking and gives a
layperson Fast, a plain register and a question budget; `ai-memory` is an
optional, detected dependency; the archive refuses a `node_modules/` tree.

Measured after, same beginner, same request, four runs: scale went from
Fast-once / Standard-twice to Fast 4/4; questions from 6–18 to 1; sub-agents
from 6–9 to 0; wall clock from 33–59 minutes to 9–15; cost from US$ 11–24 to
5–9; and every run shipped a working program with its tests green. Residual,
fixed in the last two commits and measured once: the orchestrator narrated its
test steps between tool calls, so a layperson's build turn now speaks once, at
the end.

**Minimum Claude Code:** unchanged from 0.2.0. `--serial`, the requester
profile and the memory category are prose the orchestrator follows; nothing in
the runtime moved. `subagent_type: "fork"` was measured **absent** in
`claude -p` (2.1.269 and 2.1.273) and nothing here relies on it.

### Added

- **`ai-memory` as an optional, detected dependency** (`references/mcp-integration.md`
  § Memory MCP; triage step 7a in `skills/epic/SKILL.md`; § Prior Knowledge in
  `references/context-discovery.md`; `references/run-mode.md`,
  `references/validate-mode.md`, `references/init-mode.md`; `userConfig.aiMemory`).
  One local `memory_status` call at triage — every scale, Fast included — decides
  for the whole story. When the server answers, the story is enriched at three
  points: prior knowledge before the Analyst, prior deviations and discoveries in
  every Executor's Project State, and prior structural audit findings handed to
  the Auditor as things to verify. The orchestrator writes two kinds of page from
  files that already exist — the deviation register at End of Run, structural
  audit findings after the verdict — at stable paths, so a rewrite is the
  supersession (`memory_write_page` has no `supersedes`; the path is the
  identity). When the server does not answer, nothing changes and nothing is said
  beyond one line in the proposal. Three rules are hard: memory is never evidence
  (a finding still needs the file and the line), `memory_feedback` is never
  called, and no secret is copied into a page. Sub-agents get no memory tool and
  their own `.claude/agent-memory/` stores are untouched — moving those to pages
  waits until the path-rewrite supersession has proven itself here.
- **Triage reads who is asking, and a layperson gets a plain register, a
  question budget and Fast** (`references/plain-register.md`;
  `skills/epic/SKILL.md` Triage and Clarify; `references/phase-gates.md`,
  `references/run-mode.md`, `references/preferred-tooling.md`,
  `references/init-mode.md`, `references/context-discovery.md`). Measured on a
  persona simulation of one beginner, three runs: the same request drew Fast
  once and Standard twice, and Fast served her best by every measure; the
  chat carried executor ×6, framework ×4, box ×4, commit ×8 and story ×3;
  she was asked 1 question out of her reach in Fast and 5–8 in Standard —
  how to commit on `master`, whether to version a data file, and to approve
  requirements documents she could not evaluate ("Aprovo, pode seguir",
  three times); and the same data file was gitignored in two runs and
  versioned in the third. Four changes answer those four measurements.
  - **Requester, read from the request alone, never from a question** —
    `developer` or `layperson`, `developer` when unsure. A layperson changes
    two things and nothing else: Fast is proposed and held unless they ask
    for more, and the chat switches to the plain register. Files, protocols
    and sub-agents are untouched.
  - **The plain register** — process words stay in the files and the chat
    says what happens in the requester's terms; decisions they cannot
    evaluate are taken from defaults and mentioned in one clause; a gate is
    one line, not a file review; run and show instead of "run it yourself";
    a stop promised per group is one group per turn; ~1,500 visible
    characters per turn.
  - **One question budget per story**, counted from triage to the last box
    across Clarify rounds, phase gates and run-time questions — layperson
    Fast 1 / Standard 3, developer Fast 2 / Standard 5 / Full 7. Spent
    budget means defaults and recorded assumptions, not more questions. And
    **each round is built from what the last one left open**: an
    out-of-scope answer removes its branch, a default removes its
    follow-ups, an answer in tool vocabulary re-reads the requester; when
    triage was unsure, round 1 opens with one calibration question.
  - **`## Defaults` in the constitution**, written by init whether or not
    the questions are answered — data files gitignored, tests silent in
    Fast, free text validated as text, the current branch — so the same
    request gets the same answer on every run.
- **The archive guard refuses a `node_modules/` tree, once, by directory**
  (`scripts/archive-story.sh`). Three projects in the July 2026 corpus carried
  one under `.epic/`, left by an executor's `npm install`, and every file in it
  is small enough to pass the 10 MB check on its own. The tree is now the
  offender — one violation naming the directory, its files neither scanned nor
  counted — and the guard refuses rather than deletes: nothing destructive runs
  before step 4, and a reinstallable tree is still the user's to remove.
  `--allow-heavy` archives it as it is and records the override, as for any
  other guard finding.
- **Init keeps the plugin's own litter out of the repository**
  (`references/init-mode.md`). `.epic/.gitignore` gains `node_modules/` beside
  `.draft/` and `*.wip`; and a new step, under either policy, offers — default
  yes, consent-gated, additive — to append `.claude/agent-memory/` to the root
  `.gitignore`: Claude Code writes the auditor's and analyst's project memory
  there, and a persona simulation found those notes untracked and unignored in
  a beginner's repo. Headless never edits; it logs the recommendation.

### Changed

- **A proven parallel group runs without asking** (`references/run-mode.md`).
  Detection's fourth step used to ask "Execute in parallel? [y/n]", and Run
  mode's first rule was "Sequential by default" — so the measured story ran its
  nine executors in series while the platform allows twenty. A group that
  passed the three checks (satisfied dependencies, no dependency inside the
  group, no shared file) is proven independent and is now *stated* in the
  execution plan, not asked; everything not proven runs in order as before.
  `--serial` is the one way to decline, for the whole run. The question also
  cost a round of the question budget on every run that had a group.
- **The story's evidence stays in `.draft/` by decision, and init says so**
  (`references/init-mode.md`, README). `deviations.yaml`, `red-evidence.yaml`
  and the validation and audit reports are a working record; their durable
  forms are the archive's summary and, where `ai-memory` is detected, the pages
  the orchestrator writes. Decided, not defaulted — the prior wording left it
  looking like an omission.

- **Execution routing is decided per sub-task, not read off the parent's
  `Complexity`** (`references/run-mode.md`). `Complexity` is a parent-task field
  — `references/tasks.md` makes it *Always on parent* and merely optional on the
  sub-task — so the old Execution Threshold sent every sub-task of a `Moderate`
  parent to its own Executor, the ones whose spec was already closed included.
  That is rediscovery sold as isolation: the sub-agent starts empty and re-reads
  what the orchestrator is already holding. The threshold now reads the
  sub-task's own body and takes the first matching route — verification always
  delegates (the fresh context *is* the product), exploration delegates (the
  throwaway reading dies with the sub-agent), a closed spec runs inline, and
  anything that does not say enough to route itself delegates by default.
  `Complexity` keeps the two columns the route does not decide, Tech Review and
  Context Gathering. The route changes *where* the work happens and never what
  it is: inline still runs the six steps, still gathers context when a Context
  field exists, and still closes its box through `close-subtask.sh`.
  - The two sub-sections are renamed to the routes they now describe —
    **Inline Route — Main Agent** and **Delegated Route — Executor Sub-agent**.
    "Trivial Complexity" had stopped being true of either.
- **Parallel detection runs at both levels, parent tasks and sibling sub-tasks**
  (`references/run-mode.md`). Building the graph from the parent `Dependencies`
  field alone looks for parallelism one layer above where the work is: a run
  executes sub-tasks, and a parent whose siblings are sequential can still hold
  independent sub-tasks. **Numbering is not dependency** — 2.1 and 2.2 are in
  order because a list has an order, and are dependent only when one says so.
  File conflicts stay the disqualifier, and are the usual one at this
  granularity.
- **Full is opt-in on an architectural signal, not on file count**
  (`skills/epic/SKILL.md`). The `Moderate` row of the complexity table now
  recommends **Standard**; Full asks for at least one stated signal — a new
  contract between systems, a data migration, a cross-cutting change with no
  established pattern, 2+ tracks that must be designed to fit together, or the
  user asking for it. A design doc earns its cost only when there is a decision
  to record before the code exists, and file count measures typing rather than
  design risk.
  - **Downgrade is now as legitimate as upgrade.** The upgrade rule on the
    `Simple` row gains its mirror: when clarify resolves the open questions and
    no architectural signal survives, the lighter mode is *proposed*, naming what
    the user gives up. Never silent, and never a feature demoted to a spike.
  - The triage examples in `output-styles/epic.md` and
    `references/batch-create.md` name the signal that earns their `Full`, instead
    of letting `Moderate` read as the reason.

## [0.5.0] — 2026-09-15

Twelve stories (`010`–`021`). The through-line is **one deterministic writer for
the checkbox grammar**, and then making everything that *reads* that grammar
honest: verdicts land as files instead of chat text, assertions pin direction
instead of co-occurrence, and the eval harness reports what it actually measured.

**Minimum Claude Code:** unchanged from 0.2.0. `scripts/run-evals.sh` is dev
tooling and needs a `--plugin-dir`-capable CLI; nothing in the plugin runtime
does.

### Added

- **`scripts/close-subtask.sh` — the one sanctioned writer of the checkbox
  grammar** (story `010-executor-owns-marking`). Closing a finished sub-task used
  to cost model output in the most expensive context there is: the orchestrator
  hand-edited `tasks.md`, re-read it for the census, and hand-ran the status
  transition. One invocation now marks the box, closes the parent group header
  when no open child remains, takes the census, applies run-mode's four status
  rules, stamps `status:` in every artifact carrying frontmatter, self-invokes
  `validate-story.sh`, and reports all of it as one JSON object. Its box regex
  and qualifier grammar are the existing readers' own, copied verbatim, so it is
  a *writer of* that grammar rather than a variant of it.
  - **`--fulfill "<evidence>"`** (story `021`) — the one exit from a
    `[~] (deferred: …)`. The box becomes `[x]` carrying both the evidence and the
    original reason. The line shape is forced by measurement, not taste: the
    canonical qualifier regex every reader shares matches the obvious
    `(was deferred: …)` spelling, which would have seven scripts go on counting a
    *closed* box as an outstanding deferral, and the story could never reach
    `done`.
  - **`--restate "<reason>"`** — the box does not move; only its reason does.
    For a deferral that still stands after its explanation stopped being true.
    Census unchanged, no status transition, group header untouched. It is also
    the only tool that can repair a `(deferred: )` carrying no reason at all.
  - Both accept **only** `[~]` carrying `deferred:` and refuse every other state
    by naming what they found. A terminal qualifier records a decision already
    taken, and neither flag will overwrite one.

- **Verdicts are artifacts, not chat text** (story `011-reports-by-artifact`).
  The validator and auditor write `.draft/validation-report.yaml` and
  `.draft/audit-report.yaml`; the validate flow concludes from those files. A
  sub-agent that ends on intermediate prose no longer loses the whole suite it
  just ran. The tech-reviewer gains `Bash` under a measurement-only protocol —
  its findings are measured rather than argued.

- **`stories create --batch <doc>`** (story `013-quick-create`) — one interview,
  N stories, a per-story verdict. Both create flows now draw numbers from one
  tested allocator (`scripts/next-story-number.sh`), so two stories can no longer
  claim the same number.

- **EARS form lint, `satisfied-by`, and an authoring ceiling** (story
  `014-ears-lint-authoring-ceiling`). An unlabeled acceptance criterion is an
  error — nothing downstream can trace it. A criterion carrying more than one
  `SHALL`, or a trigger word outside a code span, warns. `satisfied-by` lets a
  legitimately non-code requirement close without a task, accepted by both orphan
  sites. A plan passing **32 KB or 60 checkboxes** warns at Phase 3, at
  validation, and in batch create — a warning at every site, never a block.

- **`scripts/migrate-story.sh`** (story `015-migrate-commit-field`) — a
  dry-run-first normalizer that converts legacy stories, fence-aware, with its
  proof embedded. Five corpus variants round-trip through one apply to a clean
  validate.

- **`scripts/trigger-detect.sh`** (story `021`) — the single scorer of a trigger
  run. It reads a transcript and answers `triggered` / `not-triggered` / `error`,
  so a run that could not be measured never scores as one that did not fire.

- **`evals/README.md`** — the measurement methodology, which had no home.

### Changed

- **`Commit:` is a group field** (story `015`), not a per-sub-task one — in the
  template, in the ordering, and in every consumer copy. A group commits once,
  after its last box closes.

- **The skill `description` names every routed mode** (story `021`). `init`,
  `migrate`, `batch`, `archive`, `supersede` and `teams` were routable by the
  cascade and absent from the description, so they were unreachable by the
  phrasings they introduced. `tests/skill-description-coverage.bats` now fails on
  **either** side of a divergence — a declared term missing from the description,
  or a cascade arm with no row in the table.

- **`scripts/run-evals.sh` grades this working tree, and says how much it
  measured** (story `021`). It refuses outright when an installed plugin of the
  same name is enabled, because `--plugin-dir` does not outrank it and the suite
  would silently grade the cache. It reports `ran: N case(s), M trigger(s)`, so a
  suite that measured nothing can no longer read as a suite that passed.

- **The validator runs at `effort: medium`** (story `012-adaptive-effort`), down
  from `high`. Its work is majority-mechanical — running scripts, comparing
  outputs — while semantic judgment stays with the auditor at `max`. The full
  per-agent policy is pinned by a test, so future edits are deliberate rather
  than drift.

- **A trigger eval is no longer treated as a gate.** Measured on this repo, same
  commit and same `SKILL.md` md5: one query read **0/30** across two weeks and
  then **5/5** ten hours later, while another went **3/3 → 1/5** in the same
  window. One rose while the other fell — a routing change on the service side,
  not noise. Any gate of the form *"query X must fire"* flaps with no code
  changing, and *"no query that fired before may fail now"* fails identically
  against a tree carrying **no edit at all**: it measures the calendar, not the
  diff. Assertions belong in a deterministic lint; trigger evals belong in
  monitoring. `evals/README.md` carries the full record.

### Fixed

- **Tests that asserted nothing** (stories `019-pin-assertion-polarity`,
  `020-close-the-polarity-census`). An assertion matching *co-occurrence* passes
  whichever direction the text runs, and a negated assertion outside last
  position is inert — it cannot fail. Assertions now pin direction, and a census
  lint with a **measured allowlist** rejects a negation that cannot fail. The
  allowlist is data the suite derives, so a row naming a pattern the tree no
  longer contains is itself an error.

- **Facts an audit found stated but unmeasured** (stories `016`, `017`, `018`).
  The consumer roster became data the suite derives rather than a hand-kept list
  — an enumerated list silently drops every entry added after it.

- **A tasks-only story rendered `—` for its status.** `epic-index.sh` promised a
  fallback in its comment and only implemented it for `scale`, so every Fast
  story showed no status at all.

- **An EARS keyword is uppercase, and the check now listens for it.**

- **The legacy nudge counts what `migrate` actually converts**, not what it was
  assumed to.

- **The `shellcheck` CI job passes on the runner's shellcheck**, not only on the
  host's. Found by running the workflow locally with `act` before the branch's
  first push: the host's 0.11.0 was clean, the runner's apt 0.9.0 was not, and
  the job exits 1 even at info severity. `run-evals.sh`'s `cd … && claude … ||
  true` is now an explicit brace group — same semantics, no directive, clean on
  both versions.

## [0.4.0] — 2026-08-13

Feature release. Adds a **git-aware story lifecycle** — Epic can now tell
whether a finished story's work ever reached the main branch, and can retire a
story in favour of its replacement as a first-class operation — and moves
**supersede** and the **integration surfacing** out of orchestrator prose into
scripts a test suite can drive. Also tightens `validate` with two consistency
checks that had no detector at all.

**Minimum Claude Code:** unchanged from 0.2.0.

### Fixed

- **The interrupted-run completion is offered again, instead of just happening**
  (`scripts/supersede-story.sh`, `references/supersede-mode.md`). Wiring
  supersede behind a script had traded a prompt for an assumption: re-invoking
  `supersede NNN --by MMM` over a run that died mid-write finished it
  unconditionally, while the requirement says the system SHALL *offer* to
  complete. An operator who re-ran the command might not know a prior run was
  interrupted at all, so the second invocation carried no informed consent to
  finish a half-applied write.
  - The script now **classifies and stops**: a finishable interrupted state
    returns exit 1 with `status: "recovery-offer"`, a `reason` naming exactly
    what remains, and `banner_written: false`, `closed_subtasks: 0`,
    `artifacts_flipped: []`. **Nothing is written** — the artifacts are
    byte-identical across the offering run, which is the whole content of
    "offer".
  - **`--complete-interrupted`** authorizes the completion, and unlocks that one
    arm only: on a fresh story it changes nothing, and it can never turn a
    refusal into a completion or write a second banner.
  - The `[y/n]` and its headless branch live with the caller, exactly as the
    archive offer does. A headless session logs the offer and stops rather than
    answering on the user's behalf.
  - Exit 1 has always been documented as "refused (matrix) or **recovery
    declined**". There was no declined path until now; declining is simply not
    re-invoking with the flag, so that contract is accurate for the first time.

- **A sub-task added by `stories refine` never reached the step that records its
  Red.** Phase 3 is where the Test Advisor authors a test per `Unit`/
  `Integration`/`E2E` sub-task, confirms it fails, and records that in
  `.draft/red-evidence.yaml`. Refine is the only mode that can add a sub-task to
  a story whose Phase 3 has already run, and it stopped at propagation — so a
  refinement could ship a sub-task carrying a `Tests:` field with no authored
  test and no Red entry, and every consumer downstream was written assuming
  Phase 3 had covered the whole task list.
  - `references/refine-mode.md` gains the producing step: each added sub-task
    with a non-`None` `Tests:` field goes through the Test Advisor before the
    status census, appending to `.draft/red-evidence.yaml` rather than
    rewriting it, with `E2E` deferring its Red exactly as in Phase 3. A Red
    that cannot be established is recorded as a deviation instead of being
    invented or silently dropped.
  - `references/run-mode.md`'s materialization step gains the guard: a pending
    sub-task with a non-`None` `Tests:` field, no file under
    `.draft/authored-tests/` and no Red entry stops the Run by number rather
    than executing as if it were test-first. Copying what exists cannot see
    what is absent, so the check is stated over the plan, not over the tree.
  - `agents/auditor.md` and `references/validate-mode.md` had both phrased the
    invariant as *"every sub-task **with a pre-authored test** has an
    entry"* — a quantifier over the artifacts, which excludes precisely the
    sub-task that has no artifact. Both now quantify over the `Tests:` field
    and report a missing authored test as a finding distinct from a missing
    entry.

  Found by measurement rather than review: story `006`'s sub-task 12.3 was
  refine-added, shipped seven bats cases, and carries no `12.x` entry in its Red
  register at all.

### Added

- **Git-aware story lifecycle** (story `006-git-aware-lifecycle`). Epic can now
  tell whether a finished story's work ever reached the main branch, and can
  retire a story in favour of its replacement as a first-class operation.
  - **`scripts/story-git-status.sh`** — a new read-only detector. It emits JSON
    (`{story, main_branch, integrated, evidence, checked_at}`) from two kinds of
    git evidence: a merged `feat/NNN-*` branch (`branch-merged`), and a commit
    subject reachable from the main branch carrying the story's `(NNN)` token or
    its `NNN-slug` (`message-ref`). A bare number never counts as evidence.
    The evidence rules run in both directions. One merged branch is reported
    **once**, however many refs point at it; and two branches are never
    reported as one — a remote-tracking ref folds into a like-named local
    branch only when it is genuinely that branch's mirror, meaning its
    configured upstream or the same commit, so a fork's branch that merely
    shares a name keeps its own entry. The reported detail always names a ref
    that is itself merged, and two entries denoting different branches always
    carry details that can be told apart, so a consumer counting distinct
    details never reads two branches as one. And when a ref's remote cannot be
    told apart from its branch — a repository configuring remotes named both
    `a` and `a/b` — the detector reports the branches separately rather than
    guessing where the remote name ends and silently dropping one of them.
    **The main branch is resolved from the ref's own full path**, never from
    git's short spelling of it. That short spelling is *ambiguity-aware*: it
    changes as soon as any unrelated ref claims the same name. So a stray
    branch or tag called `origin/main` used to corrupt both the reported
    `main_branch` and the revision the evidence was searched on, reporting an
    integrated story as un-integrated and putting the mangled name into the
    validate warning's text. Adding an unrelated ref now changes neither
    answer.
    And **"not integrated" is now only ever said about a story that was
    actually checked.** Resolving the main branch answers two separate
    questions — what it is *called*, and which revision to search — and a
    repository can answer the first while the second points at nothing: a
    `git fetch --prune` that deletes `origin/main` leaves the pointer naming it
    behind. Both evidence searches then fail, and the empty result used to be
    reported as a finding, so validate warned about a story nothing had managed
    to look at. That case now reports the integration as **unknown**, which
    every consumer passes over in silence, while still reporting the branch
    name it did resolve.
    Everything is **evaluated live and stored nowhere** — no commit SHA, branch
    name or merge-base is ever written into an artifact, so the answer can never
    go stale. A project that is not a git repo, or has no main branch that can
    be searched, degrades silently: no annotation, no warning, no error.
  - **`references/list-mode.md`** and **`references/validate-mode.md`** — the
    signal is **surfaced, never enforced**. LIST annotates the status cell of
    each `done` / `validated` story (skipped above 50 stories unless the command
    is `stories full`, since each annotation costs one git evaluation), and a
    passing validate appends an integration warning before anything acts on the
    verdict. Neither changes a verdict, a status write or an exit code, and
    neither gates the archive.
  - **`/epic:epic stories supersede NNN --by MMM`** — a new first-class
    operation (**`references/supersede-mode.md`**, routed from
    **`skills/epic/SKILL.md`**, listed in **`README.md`**). It prepends a
    standardized ⛔ banner to `NNN` carrying the date, the replacement story, a
    one-line rationale and one remap row per open sub-task; writes
    `status: superseded` plus the machine-readable companion
    `superseded-by: MMM` into every `NNN` artifact; closes each open sub-task as
    `[~] (superseded-by: MMM)`; regenerates the index; and offers the archive on
    the spot. `MMM` must already exist, so a typo in `--by` can never mint a
    story. A story that already carries a banner gets one of three answers, and
    the banner is written at most once whichever it is: a re-run over a
    **completed** supersede refuses, an **interrupted** one is offered
    completion of only its remaining steps, and a story whose frontmatter was
    written while its scope was still open — a shape this command cannot
    produce — refuses and says so rather than being offered a completion
    supersede could not honestly perform.
    - **The verbatim rule is stated rather than assumed** (`references/supersede-mode.md`,
      new *The verbatim rule* section). The mode tells the session to surface a
      refusal's `reason` verbatim; it now says what "verbatim" permits — a
      `Refused: ` lead-in and a closing full stop are the session's own
      presentation, and everything between them is the script's text, the story
      slug included. The worked example previously rendered `story 042` where
      the JSON says `story 042-legacy-import`, dropping exactly the token that
      distinguishes two story directories sharing a number; the example now
      quotes the reason whole.
  - **`references/tasks.md`** — commit guidance gains the story anchor the
    detection reads: `type(NNN): subject` for commits, `feat/NNN-slug` for
    branches. A recommendation, not an enforcement — nothing gates on the shape.
  - **`scripts/story-git-status.sh` JSON escaping** — the emitter escapes the
    full C0/C1 control range as `\uXXXX`, so a control character in a commit
    subject can no longer make the emitted document unparseable by `jq`.
- **Supersede and the integration surfacing gained entry points**
  (**`scripts/supersede-story.sh`**, **`scripts/render-integration.sh`**). Both
  operations were specified as orchestrator prose, which meant no test could
  drive them and every claim about their behaviour rested on reading. The steps
  that **write to artifacts** — the refusal matrix, the banner and its
  idempotence, the remap rows, the sub-task closures, the `status:` /
  `superseded-by:` writes, and the interrupted-run classification — now live in
  a script with `archive-story.sh`'s exit conventions — `0` superseded, `1`
  refused, `2` invalid input — and one JSON object on stdout on every path that
  reaches a verdict. It is **silent on stderr** wherever it emits JSON, unlike
  `archive-story.sh`: a diagnostic beside the object breaks any caller that
  pipes stdout into `jq`, and the supersede *conversation* belongs to the
  orchestrator, which reads `reason` out of the report and says it in the
  session's own voice. The steps that are **decisions** stay a conversation: the
  rationale, the remap targets and the archive offer are inputs, not behaviour.
  The LIST annotation and the validate warning are a pure function of the
  detector's JSON, so they are a script too — one that exits `0` on every path,
  because a renderer that can fail lets a caller turn a warning into a verdict.
- **Those entry points are now on the path the commands take.** They shipped
  wired to nothing: `references/supersede-mode.md`, `references/list-mode.md`
  and `references/validate-mode.md` still described the behaviour in prose, so
  the copy the suite exercised was not the copy the command ran. All three now
  **invoke** the scripts, and the prose tables they used to render from are
  demoted to documentation of what the scripts emit. **One user-visible
  behaviour changes with it, and it is a loss:** completing an interrupted
  supersede used to be offered, because the orchestrator performed those steps
  by hand; the script completed unconditionally on re-invocation instead, and
  had no prompt anywhere. **That loss is repaired below in this same release —
  see "The interrupted-run completion is offered again" under Fixed.** The gap
  was recorded rather than papered over, and it was owed a fix rather than an
  amendment; it got one.
- **`scripts/validate-story.sh` — a status can no longer lag its checkboxes in
  silence.** The validator already warned when a story claimed `done` over an
  open box; the converse was *prevented* by Run mode rather than *detected* by
  anything, so when the prevention failed to fire nothing reported it — and a
  story that has finished every task while still reading `in-progress` is never
  offered the archive. A story whose census shows no open `[ ]` **and no
  deferred `[~]`** while its status reads `draft` or `in-progress` now warns. A
  **deferred** box deliberately blocks `done`, so a story resting over one is
  correct and stays silent; `superseded` and `archived` are terminal and are
  exempt for the same reason. Warning, never error.
- **`skills/epic/SKILL.md` — the 10-entry history cap no longer applies to
  artifacts that are not in git.** The rule relegates older entries to "see git
  history", and relegation needs a destination. Where `.epic/` is gitignored —
  the default this plugin ships — dropping the eleventh entry destroys it, so
  the cap is lifted there and holds unchanged wherever the artifacts are
  tracked.
- **`scripts/validate-story.sh` — a group header can no longer lie about its own
  sub-tasks.** A task group's checkbox is a claim about the sub-tasks under it,
  and nothing checked it: a group left `- [ ]` over sub-tasks that are all
  closed, or marked `- [x]` over a sub-task still open, validated clean. Both
  are now **errors**, because the rule is an identity and half an identity is
  not one. `[~]` is untouched — a group closed without doing the work is a
  legitimate third state and neither direction applies to it — and a group with
  no sub-tasks has nothing to be consistent with. Sub-tasks belong to a group by
  their number, so group `1` owns `1.1` and never `10.1`, and a **repeated**
  group number is its own error rather than one header quietly replacing the
  other. Two parts of a `tasks.md` are excluded from the check, because a group
  header is not the only thing shaped like one: **Quality Gates** (which share
  the checkbox grammar by design, so `- [ ] 3 - Coverage >= 80%` is a legal gate
  and a plausible header at once) and **fenced code blocks** (where a task list
  is an illustration, not a claim). Neither exclusion depends on how a heading
  is spelled or on locating where a section ends. The box counts everything else
  depends on are unaffected — they still cover the whole file. Where a group's
  state cannot be read at all — an unqualified
  `[~]` child, or two headers claiming one number — the check says so instead
  of guessing. The practical effect is on the archive gate: a group header left
  open over finished work reads as pending to `archive-story.sh`,
  `monitor-stale.sh` and the precompact hook alike, and the archive is the one
  that refuses on it.

## [0.3.1] — 2026-05-17

Patch release. Fixes plugin metadata so the version is shown in the Claude Code
plugin UI.

**Minimum Claude Code:** unchanged from 0.2.0.

### Fixed

- The plugin entry in `.claude-plugin/marketplace.json` was missing a `version`
  field, so the **Plugins → Installed** details view displayed no version.
  Added `"version"` to the marketplace entry, kept in sync with
  `plugin.json`.

## [0.3.0] — 2026-05-17

Feature release. Adds **Fast-mode run-time test-first execution** and an
opinionated **preferred-tooling policy** for E2E tool selection across all
modes.

**Minimum Claude Code:** unchanged from 0.2.0.

### Added

- **Fast-mode run-time test-first execution** (story `002-fast-mode-test-first`).
  A Fast sub-task carrying a `Tests` field now has its test authored and
  confirmed failing (**Red**) before implementation, then proceeds
  **Green-then-Refactor**. Test authoring happens at run time and is
  single-author — the main agent writes the test directly; no `test-advisor`
  sub-agent is involved (that pipeline remains Standard/Full only).
- **Optional Fast-only `Acceptance` field** — 1-3 observable-behaviour
  statements on a Fast sub-task. Every implementing (non-Commit) Fast sub-task
  now carries either a `Tests` field or an `Acceptance` field.
- Standard and Full mode test-first behaviour is **unchanged**.
- **`agents/executor.md`** is reused **unmodified** — its existing conditional
  six-step protocol already consumes a pre-authored test (step 5 Refactor for a
  sub-task with a pre-authored test, Tests otherwise).
- **Preferred-tooling policy** (story `003-preferred-tooling-policy`).
  - **`references/preferred-tooling.md`** — a new opinionated policy reference.
    Favorite E2E tools are `playwright` and `chrome-devtools`; optional E2E
    tools are `puppeteer`, `selenium`, `browser-use` and `stagehand`. Detection
    uses three mechanisms — MCP health-check, dependency-manifest inspection,
    and skill-list presence — and runs in **all modes, including Fast**. When no
    favorite is installed the policy is recommend-and-pause: Epic surfaces a
    recommendation and waits rather than silently selecting an optional tool.
  - **`skills/epic/SKILL.md`** — triage gains step 7b "Detect preferred
    tooling", a `### Preferred Tooling` subsection, and a `> - Tooling:`
    proposal line. The resolved selection is persisted to `design.md`'s
    `## Tooling Decisions` block.
  - **`agents/test-advisor.md`** — the Test Advisor now also authors `E2E` test
    files (in addition to `Unit` and `Integration`), using the story's selected
    E2E tool. Red-phase verification for an `E2E` test is **deferred to Run
    mode**, which confirms the deferred Red before implementation and Green
    after. The `frontend-design` skill is the preferred frontend implementation
    aid when installed.

## [0.2.0] — 2026-05-17

Feature release. Introduces **test-first execution with independent test
authorship**, narrows the plugin's purpose with an explicit scope contract,
makes MCP selection cost-aware, and adds agent-teams flag-mismatch detection.
Ships a **breaking command rename** — `/epic:task` is now `/epic:epic`.

**Minimum Claude Code:** unchanged from 0.1.5 (v2.1.105 for the full
capability surface; degraded operation on v2.1.85+).

### Changed

- **BREAKING — the command is renamed `/epic:task` → `/epic:epic`.** The skill
  directory moved `skills/task/` → `skills/epic/`, and every reference across
  docs, `references/*`, evals, monitors and output styles was updated. Existing
  `/epic:task` invocations no longer resolve — use `/epic:epic`.
- **`references/mcp-integration.md`** — MCP selection is now cost-aware. A
  priority order (`context7` > `brave-search` > `exa` > `tavily` > `firecrawl`)
  replaces flat detection; `perplexity` is demoted to a last-resort option and
  is no longer health-checked by default, since each query is paid.
- **`.gitignore`** — ignores the entire `.claude/` directory (local settings
  and sub-agent agent-memory), not just `.claude/settings.local.json`.

### Added

- **Test-first execution with independent test authorship** (story
  `001-test-first-execution`). Standard and Full stories now execute test-first:
  - **`agents/test-advisor.md`** — becomes a failing-test author. Gains the
    `Write` and `Bash` tools (`maxTurns` 15→30, `effort` medium→high). For each
    Standard/Full sub-task whose Tests field is Unit or Integration it authors
    one failing test into the story's `.draft/authored-tests/`, runs it to
    confirm it fails (Red), and records `.draft/red-evidence.yaml`. It receives
    the EARS requirement, Objective, Tests scenarios and — Full only — the
    `design.md` contract, but never the `ToDo` field. An unexpected-green test
    is revised up to 2 times, then escalated to the user.
  - **`agents/executor.md`** — the protocol keeps six steps, but step 5 is now
    conditional: **Refactor** for a sub-task with a pre-authored test (improve
    code while the test and validation stay green), **Tests** for one without.
    Adds a frozen-test rule (assertions immutable; imports / signature
    call-sites adjustable only for an intentional design deviation, recorded
    with `test_surface_adjusted: true`) and behavior-deviation escalation.
  - **`agents/auditor.md`** — new audit check #10: every sub-task with a
    pre-authored test must have a Red-evidence entry recorded before
    implementation.
  - **`references/run-mode.md`** — an idempotent test-materialization step
    (copies `.draft/authored-tests/**` into the real test tree, skip-and-warn
    on existing paths) and a read-only Pre-Authored Test input in the Executor
    prompt template.
  - **`references/phase-gates.md`**, **`references/validate-mode.md`**,
    **`references/tasks.md`** — orchestration prompt templates and the Tests
    field documentation updated to match the new authoring role.
- **`PURPOSE.md`** + a hard-refusal scope table in `skills/epic/SKILL.md` —
  Epic now states a single narrow purpose (create, structure and manage epics
  and their stories) and refuses out-of-scope requests (code review, refactor,
  debug, ad-hoc analysis) with a pointer to the correct Claude Code command.
- **`skills/epic/SKILL.md`** — a runtime dependency precheck for
  `AskUserQuestion` and `TaskCreate` / `TodoWrite` before Standard/Full triage,
  with explicit fallbacks and no silent degradation; frontmatter gains the
  `Task*` tools.
- **`hooks/hooks.json`** — `SessionStart` and `UserPromptSubmit` hooks
  (`hook-teams-session-start.sh`, `hook-teams-prompt-submit.sh`) that detect a
  stale `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag (set in settings but not
  active in the running session) and escalate over two prompts before
  disabling it.

## [0.1.5] — 2026-04-19

CI hotfix. Resolves three shellcheck warnings that were failing the
`shell-ci` workflow on `main` after v0.1.4. No behavioural changes to
the plugin or scripts.

**Minimum Claude Code:** unchanged from 0.1.4.

### Fixed

- **`scripts/run-evals.sh`** — SC2155: separated `local workdir`
  declaration from its command-substitution assignment so the subshell's
  exit status is no longer masked by `local`.
- **`scripts/run-evals.sh`** — SC2015: replaced
  `cd "$workdir" && claude ... || true` with an explicit
  `if cd "$workdir"; then claude ... || true; fi` block so control flow
  on `cd` failure is unambiguous.
- **`scripts/validate-story.sh`** — SC2034: removed the unused
  `HAS_DESIGN` variable. It was assigned but never read, since
  `design.md` presence is not required for structural validation.

## [0.1.4] — 2026-04-19

Documentation-only release. Introduces a dedicated `ARCHITECTURE.md` covering
the conceptual model, sub-agent pipeline, artifact contracts, hook matrix,
executor protocol, validation layers, and architectural decisions — content
previously scattered across `references/*` and inline agent prompts. No code
or behavioural changes.

**Minimum Claude Code:** unchanged from 0.1.3 (v2.1.105 for full capability
surface; degraded operation on v2.1.85+).

### Added

- **`ARCHITECTURE.md`** — design-level contributor guide at the repo root.
  Documents the Plan → Execute → Verify pipeline, which persona activates at
  each scale, artifact/frontmatter/cross-reference contracts, the hook matrix
  with per-event minimum CC versions, the executor 6-step protocol, the four
  validation layers (artifact, cross-reference, task, audit), story-directory
  lifecycle, and rationale for 9 architectural choices (bash-only scripts,
  single-skill routing, scale-adaptive modes, English-only artifacts,
  plugin-scope hooks, archive immutability via PreToolUse, agent-teams as
  opt-in, `defer` for headless commits, graceful MCP degradation).

## [0.1.3] — 2026-04-19

Adopt new Claude Code 2.1.105 capabilities across the plugin surface. All
changes are additive and backwards-compatible — older Claude Code versions
continue to work with degraded ergonomics (see README "Minimum Claude Code
version per component" table).

**Minimum Claude Code:** v2.1.105 for the full new capability surface.
Degraded operation on v2.1.85+.

### Added

- **README** — per-component minimum-version table covering conditional hooks,
  skill `effort`, `EnterWorktree.path`, plugin monitors, plugin `bin/`, output
  styles, `PermissionDenied` retry, `defer` commit gating, agent-teams,
  `--bare`, and `disableSkillShellExecution`.
- **`hooks/hooks.json`** — three new hook events:
  - `PostToolUseFailure(matcher: Bash)` → `hook-post-tool-failure.sh` (injects
    executor protocol reminder when a Bash command fails mid-story).
  - `CwdChanged` → `hook-cwd-changed.sh` (orients on `cd` into a `.epic/`
    project: surfaces story counts and constitution head).
  - `FileChanged(matcher: constitution.md)` → `hook-file-changed.sh`
    (re-surfaces constitution head when modified outside the session).
- **`hooks/hooks.json`** — `asyncRewake: true` on `TaskCompleted` so the
  validate re-run does not block the foreground.
- **`agents/auditor.md`** — `LSP` tool added; project-scoped memory declared
  for recurring scope-creep patterns and false-positive deviations.
- **`agents/analyst.md`** — project-scoped memory declared for accumulated
  pattern findings; documented `Explore` agent as a faster alternative for
  Function 1 when memory continuity is not required.
- **`skills/epic/SKILL.md`** — `AskUserQuestion` added to allowed-tools; Clarify
  Protocol reworked to use multiple-choice prompts (with legacy
  numbered-assertion fallback when the tool is unavailable). Architectural note
  documents why hooks live at plugin scope rather than skill frontmatter.
- **`references/ci-mode.md`** — typed `--json-schema` validation example for
  CI gating; `system/init` event recipe for detecting plugin load failures
  from `--output-format stream-json --verbose`.
- **`scripts/`** — `hook-cwd-changed.sh`, `hook-file-changed.sh`,
  `hook-post-tool-failure.sh`.

### Changed

- **`scripts/monitor-stale.sh`** — clarifies that the Claude Code runtime
  (not the script) is responsible for skipping plugin monitors on
  Bedrock/Vertex/Foundry and when `DISABLE_TELEMETRY` /
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` are set.

## [0.1.2] — 2026-04-19

### Fixed
- **`plugin.json` userConfig schema** — install was failing with `Validation errors: userConfig.*.type: Invalid option ...` because each entry now requires `type` (one of `string` | `number` | `boolean` | `directory` | `file`) and `title`. Added both fields to all five userConfig entries and converted numeric defaults from string (`"7"`, `"3600"`) to number (`7`, `3600`).

## [0.1.1] — 2026-04-19

### Added
- **`.claude-plugin/marketplace.json`** — enables one-line install via `/plugin marketplace add lucascouts/epic` + `/plugin install epic@lucascouts`. Marketplace name: `lucascouts`; plugin `epic` sourced from the same repo (`source: "./"`).

## [0.1.0] — 2026-04-19

Initial public release. Internal pre-public history (referenced in `references/teams-mode.md` as "1.3.0 → 1.4.0") is collapsed into this release.

**Minimum Claude Code:** v2.1.105 for full capability surface (plugin monitors with `when:`, `PreCompact` hook, `EnterWorktree.path`, skill description cap of 1,536 chars, `effort` field on skills/agents). Degraded operation on v2.1.85+ (no compact recovery; conditional hooks still work; monitors absent).

### Plugin manifest (`plugin.json`)

- Top-level metadata: `name`, `version`, `description`, `author`, `license`, `homepage`, `repository`, `keywords`.
- **`userConfig`** with 5 options (all non-sensitive, exported as `CLAUDE_PLUGIN_OPTION_*` env vars):
  - `defaultScale` (string, default `"standard"`) — fallback mode when triage cannot determine complexity
  - `artifactLanguage` (string, default `"en"`) — override only if the organisation mandates non-English artifacts
  - `enableStaleMonitor` (boolean, default `false`) — opt-in for the stale-story background watcher
  - `staleThresholdDays` (number, default `7`) — days of inactivity before a story is flagged
  - `staleCheckIntervalSeconds` (number, default `3600`) — poll cadence

### Marketplace (`marketplace.json`)

- Single-plugin marketplace named `lucascouts`, sourced from the same repo (`source: "./"`).

### Skill — `/epic:epic`

- Scale-adaptive workflow with three modes (Fast / Standard / Full) and two workflow variants (Requirements-First / Design-First).
- Sub-routes: `init`, `stories`, `stories full`, `stories NNN`, `stories run NNN [--auto|--batch=N|--gate=commit]`, `stories validate NNN`, `stories refine NNN`, `stories archive NNN[-MMM]|--done`, `stories teams {status|enable|disable}`, `archive`.
- Frontmatter uses `effort: max`, `paths: [".epic/**", "tasks.md", "story.md"]`, full `allowed-tools` whitelist (incl. `EnterWorktree`/`ExitWorktree`).
- Inline shell `!` blocks for project-state context (existing stories, constitution head, git HEAD); falls back gracefully when `disableSkillShellExecution: true`.

### Sub-agents (8)

| Agent | Role | Activated for |
|---|---|---|
| `analyst` | Codebase scan, completeness checklist | Standard + Full |
| `architect` | Pattern research, gotcha capture | Full |
| `test-advisor` | Defines tests per sub-task | Standard + Full (Phase 3) |
| `reviewer` | Cross-artifact review | Full |
| `executor` | 6-step implementation protocol | Simple+ tasks (all scales) |
| `tech-reviewer` | Multi-tech boundary correctness | All scales (multi-tech) |
| `validator` | Runs validation commands | All scales |
| `auditor` | Story/design fidelity, scope creep | All scales |

All agents declare `model: inherit`, `tools` whitelist, `maxTurns`, and `effort` calibrated by role.

### Hooks (7 events, all `if:`-filtered or matcher-scoped)

- `PostToolUse(Write, if: Write(.epic/**))` → `validate-story.sh`
- `PreToolUse(Edit|Write, if: Edit/Write(.epic/archive/**))` → blocks edits to archive
- `PreToolUse(Bash, if: Bash(git commit *))` → `permissionDecision: "defer"` in CI/headless
- `PreCompact` → snapshots active story to `.draft/compact-snapshot.md` _(requires v2.1.105)_
- `SessionStart(compact)` → re-injects snapshot into context
- `SessionEnd(clear)` → cleanup
- `TaskCompleted` → re-runs validate against active story
- `PermissionDenied(matcher: mcp__.*)` → returns `{retry: true}` _(requires v2.1.89)_

### Plugin monitors (1, opt-in)

- `epic-stale-stories` (`when: on-skill-invoke:task`) — surfaces stories with no progress past `staleThresholdDays`. Requires `enableStaleMonitor: true` and Claude Code v2.1.105+.

### Output style (1, opt-in)

- `epic` style for triage proposals, phase gates, run reports, validator/auditor output. Declares `keep-coding-instructions: true` _(requires v2.1.94)_.

### `bin/` executables (PATH-exposed)

- `epic-validate` (wrapper around `validate-story.sh`)
- `epic-xref` (wrapper around `cross-reference.sh`)

_(Plugin `bin/` requires Claude Code v2.1.91+.)_

### Scripts (10)

- `validate-story.sh`, `cross-reference.sh` — validation engines (JSON output, exit 0/1/2).
- `hook-validate.sh`, `hook-archive-guard.sh`, `hook-defer-commit.sh`, `hook-precompact.sh`, `hook-session-restore.sh`, `hook-task-completed.sh`, `hook-session-end-cleanup.sh` — hook implementations.
- `monitor-stale.sh` — opt-in background watcher.
- `teams-config.sh` — manages `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag in `.claude/settings.local.json`.
- `run-evals.sh` — runs the eval suite.

### References (17 markdown files)

- Mode-specific operational guides: `init-mode.md`, `list-mode.md`, `run-mode.md`, `validate-mode.md`, `refine-mode.md`, `ci-mode.md`, `teams-mode.md`.
- Methodology: `ears-notation.md`, `requirements.md`, `design-guide.md`, `tasks.md`, `bugfix.md`, `bugfix-design.md`, `phase-gates.md`, `self-review-checklist.md`, `context-discovery.md`, `mcp-integration.md`, `constitution.md`.

### Examples & evals

- `assets/examples/`: `fast-feature.md`, `standard-feature.md`, `full-feature.md`, `bugfix-complete.md`.
- `evals/`: 6 cases + 24 trigger queries with `run-evals.sh`.

### Tests & CI

- `tests/`: `validate-story.bats`, `teams-config.bats` (bats unit tests).
- `.github/workflows/shell.yml`: shellcheck + bats + example validation.

### Agent-teams integration (experimental, opt-in)

- During Full-mode triage with 2+ independent tracks, offers `[y]/[n]/[never]` proposal to enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` _(requires v2.1.32)_.
- Teammates reuse the `executor` agent definition (one per track, in its own context).
- `/epic:epic stories teams {status|enable|disable}` for direct flag management.
- Per-project opt-out via `.epic/teams-opt-out` sentinel file.

[Unreleased]: https://github.com/lucascouts/epico/compare/v0.27.1...HEAD
[0.27.1]: https://github.com/lucascouts/epico/compare/v0.27.0...v0.27.1
[0.27.0]: https://github.com/lucascouts/epico/compare/v0.26.1...v0.27.0
[0.26.1]: https://github.com/lucascouts/epico/compare/v0.26.0...v0.26.1
[0.26.0]: https://github.com/lucascouts/epico/compare/v0.25.1...v0.26.0
[0.25.1]: https://github.com/lucascouts/epico/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/lucascouts/epico/compare/v0.24.0...v0.25.0
[0.24.0]: https://github.com/lucascouts/epico/compare/v0.23.1...v0.24.0
[0.23.1]: https://github.com/lucascouts/epico/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/lucascouts/epico/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/lucascouts/epico/releases/tag/v0.22.0
[0.21.0]: https://github.com/lucascouts/epico/releases/tag/v0.21.0
[0.20.0]: https://github.com/lucascouts/epico/releases/tag/v0.20.0
[0.19.0]: https://github.com/lucascouts/epico/releases/tag/v0.19.0
[0.18.0]: https://github.com/lucascouts/epico/releases/tag/v0.18.0
[0.17.0]: https://github.com/lucascouts/epico/releases/tag/v0.17.0
[0.16.0]: https://github.com/lucascouts/epico/releases/tag/v0.16.0
[0.15.0]: https://github.com/lucascouts/epico/releases/tag/v0.15.0
[0.14.0]: https://github.com/lucascouts/epico/releases/tag/v0.14.0
[0.13.1]: https://github.com/lucascouts/epico/releases/tag/v0.13.1
[0.13.0]: https://github.com/lucascouts/epico/releases/tag/v0.13.0
[0.12.0]: https://github.com/lucascouts/epico/releases/tag/v0.12.0
[0.11.1]: https://github.com/lucascouts/epico/releases/tag/v0.11.1
[0.11.0]: https://github.com/lucascouts/epico/releases/tag/v0.11.0
[0.10.0]: https://github.com/lucascouts/epico/releases/tag/v0.10.0
[0.9.0]: https://github.com/lucascouts/epico/releases/tag/v0.9.0
[0.8.0]: https://github.com/lucascouts/epico/releases/tag/v0.8.0
[0.7.0]: https://github.com/lucascouts/epico/releases/tag/v0.7.0
[0.6.0]: https://github.com/lucascouts/epico/releases/tag/v0.6.0
[0.5.0]: https://github.com/lucascouts/epico/releases/tag/v0.5.0
[0.4.0]: https://github.com/lucascouts/epico/releases/tag/v0.4.0
[0.3.1]: https://github.com/lucascouts/epico/releases/tag/v0.3.1
[0.3.0]: https://github.com/lucascouts/epico/releases/tag/v0.3.0
[0.2.0]: https://github.com/lucascouts/epico/releases/tag/v0.2.0
[0.1.5]: https://github.com/lucascouts/epico/releases/tag/v0.1.5
[0.1.4]: https://github.com/lucascouts/epico/releases/tag/v0.1.4
[0.1.3]: https://github.com/lucascouts/epico/releases/tag/v0.1.3
[0.1.2]: https://github.com/lucascouts/epico/releases/tag/v0.1.2
[0.1.1]: https://github.com/lucascouts/epico/releases/tag/v0.1.1
[0.1.0]: https://github.com/lucascouts/epico/releases/tag/v0.1.0
