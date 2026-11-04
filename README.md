# Epico — Structured Story Framework for Claude Code

Scale-adaptive plugin for creating, managing, and executing development work as structured stories (features and bugfixes). Epico turns vague requests into EARS-notation requirements, design documents, and a tracked task list — then orchestrates specialized sub-agents to implement, validate, and audit the work.

Invoked as `/epico:epico` inside Claude Code.

> **Scope is narrow.** Epico creates, structures, and manages epics/stories — nothing else. It does **not** perform ad-hoc code review, security review, refactors outside a planned story, general analysis, or exploratory code generation. See [PURPOSE.md](PURPOSE.md) for the full in-scope / out-of-scope contract and which Claude Code command to use for each refused case.

---

## Why Epico

Ad-hoc prompts lose context, drift in scope, and produce undocumented changes. Epico formalizes the loop:

- **Plan**: EARS requirements (`SHALL ...`), optional design doc with component interfaces, hierarchical tasks with validation commands.
- **Execute**: the main agent writes production code inline; the `executor` sub-agent writes it only in a parallel group, and otherwise takes only work that needs nothing from the session's context — a test from the spec, a disposable file. Either follows a strict 6-step protocol per sub-task (context → implementation → design fidelity → validation → refactor-or-tests → report). Step 5 is conditional: Refactor when the sub-task carries a pre-authored failing test, Tests when it does not.
- **Verify**: one Auditor spawn runs every validation command, then cross-checks code against story and design for scope creep, deviations, and unmet quality gates.

Scale is chosen per request:

| Mode | Artifacts | When |
|---|---|---|
| **Fast** | `tasks.md` only | 1–2 files, trivial scope |
| **Standard** | `story.md` + `tasks.md` | 2–5 files, clear scope |
| **Full** | `story.md` + `design.md` + `tasks.md` | 5+ files, design decisions, integrations |

All three modes are **test-first**. Standard and Full at engineering level `project` or `product` author tests at plan time — the Test Advisor writes one failing test per Integration/E2E sub-task in Phase 3, and per Unit sub-task in Full (in Standard the Executor writes Unit tests first, at run time); at `experiment` or `tool` they write them at run time, as Fast does. For an E2E sub-task the Test Advisor uses the story's selected E2E tool and **defers Red-phase verification to Run mode** (Run confirms the deferred Red before implementation and Green after). Fast mode is **test-first at run time and single-author**: a Fast sub-task carrying a `Tests` field has its test authored by the main agent and confirmed failing (Red) before implementation, then Green-then-Refactor — no Test Advisor sub-agent. A Fast sub-task with no testable logic carries an optional Fast-only `Acceptance` field instead — 1–3 observable-behavior statements; every implementing (non-Commit) Fast sub-task carries either a `Tests` field or an `Acceptance` field. Fast keeps its lightweight scale: no `story.md`, no design, no gate, no `.draft/`.

**Scale is one axis; the engineering level is the other.** Triage also reads how long the thing must last — `experiment` (disposable, 1×), `tool` (kept and fixed, 2–3×), `project` (maintained, others depend on it, 4–6×), `product` (may be published or sold, 8×+) — proposes it with its price in one line, and from it sets which tier of the quality catalog the story activates, whether Phase 3 authors the tests or the run does, and the plan's box ceiling (5, 12, 24, 40 Task List boxes). The level never changes the scale. See [references/engineering-level.md](references/engineering-level.md).

Epico ships an opinionated **preferred-tooling policy** ([references/preferred-tooling.md](references/preferred-tooling.md)) for E2E test tooling. Triage detects installed E2E tools — favorites are `playwright` and `chrome-devtools` — via MCP health-check, dependency-manifest inspection, and skill-list presence, in **all modes including Fast**. When no favorite is found, Epico recommends one and pauses rather than silently picking an optional tool (`puppeteer`, `selenium`, `browser-use`, `stagehand`). The resolved choice is persisted to `design.md`'s `## Tooling Decisions` block.

---

## Installation

### Marketplace (recommended)

Inside Claude Code:

```
/plugin marketplace add lucascouts/epico
/plugin install epico@lucascouts
```

Or from a shell:

```bash
claude plugin marketplace add lucascouts/epico
claude plugin install epico@lucascouts
```

### Local (development)

```bash
git clone https://github.com/lucascouts/epico.git
claude --plugin-dir ./epico
```

Run `/reload-plugins` after updating plugin files.

### Prerequisites

- **Claude Code v2.1.295 or newer.** One floor for every feature: the fail-closed guards (`onFailure`), the sub-agent status line, `LSP` in a background sub-agent and the plugin options all need it. Older versions are not supported.
- `bash`, `jq` and git 2.31 or newer available on PATH (2.31 names the common git directory by absolute path, where the [reuse ledger](#check-reuse) lives); `setsid` and `timeout` to run a check
- **Optional MCPs** for web research: `brave-search`, `exa`, `tavily`, `firecrawl`, and `perplexity` (premium, never the default). Epico health-checks each MCP before suggesting it; missing MCPs degrade gracefully. Library docs need no MCP: Epico reads the installed dependency first, then the official docs for that version.
- **Optional — keep sub-agents in the foreground:** in interactive sessions Claude Code runs sub-agents in the background by default, and Epico then waits for each one's completion notification. To run them in the foreground instead, start Claude Code with `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` (or put it in your settings `env`). Side effect: no background Bash commands and no Ctrl+B.
- **Optional tooling for development**: `shellcheck` and `bats` for running the script test suite locally (`bats tests/`).

---

## Quickstart

```bash
# 1. Initialize project configuration (wizard)
/epico:epico init

# 2. Create a story (triage proposes scale, you confirm)
/epico:epico Add email verification to the user signup flow

# 3. List stories
/epico:epico stories

# 4. Run tasks of story 001
/epico:epico stories run 001

# 5. Validate the implementation against story + design
/epico:epico stories validate 001

# 6. Archive validated stories
/epico:epico stories archive 001
```

Artifacts live in `.epico/stories/NNN-kebab-case/`. Whether git tracks them is an explicit choice the `init` wizard asks for once, per project — see [Versioning policy for `.epico/`](#versioning-policy-for-epic).

---

## Command Reference

| Command | Purpose |
|---|---|
| `/epico:epico` | Create story from free-text description (triage + clarify + phases) |
| `/epico:epico init` | Set up `.epico/constitution.md`, offer deny rules for files Claude must not edit, ask the [versioning policy](#versioning-policy-for-epic) question (for `CLAUDE.md`, use the built-in `/init`) |
| `/epico:epico stories` | List all stories (summary) |
| `/epico:epico stories full` | List all stories with tasks |
| `/epico:epico stories NNN` | Show one story in detail |
| `/epico:epico stories run NNN` | Execute pending tasks of story NNN |
| `/epico:epico stories run NNN --auto` | Run non-stop, only halt on a failure or an uncovered doubt — the default for a Fast story |
| `/epico:epico stories run NNN --step` | Gate after every task group in a Fast run |
| `/epico:epico stories run NNN --batch=N` | Gate every N task groups |
| `/epico:epico stories run NNN --gate=commit` | Gate only at Commit sub-tasks |
| `/epico:epico stories run NNN --serial` | No parallel groups — every task in order, whatever detection finds |
| `/epico:epico stories validate NNN` | Validate and audit NNN (one Auditor spawn) |
| `/epico:epico stories refine NNN` | Delta refinement (versioned) |
| `/epico:epico stories supersede NNN --by MMM` | Replace story NNN with MMM via `references/supersede-mode.md` — supersede banner, per-task remap, `superseded` status in every artifact, archive offer |
| `/epico:epico stories archive NNN[-MMM]\|--done` | Archive validated stories via `scripts/archive-story.sh` (anything else needs `--force <reason>`) — guarded move, pruned evidence, derived manifest entry |

---

### Sub-agents

| Agent | Role |
|---|---|
| `analyst` | Codebase scan at triage (the completeness checklist is written by the main agent) |
| `test-advisor` | Defines testing requirements per sub-task and authors one failing test per Unit/Integration/E2E sub-task with Red-phase verification — E2E tests use the story's selected E2E tool with Red verification deferred to Run mode (Phase 3, Standard + Full at `project`/`product` level) |
| `reviewer` | Cross-artifact review — gaps, consistency, orphan wiring (Full mode) |
| `executor` | 6-step implementation protocol (context → implementation → design fidelity → validation → refactor-or-tests → report); step 5 is conditional — Refactor for a test-first sub-task, Tests for a test-after one. The report ends in a machine-liftable **closing block** (sub-task id, outcome `done` / `close-tilde` + qualifier + reason / `failed`, pre-authored commit message; `failed` closes nothing). It marks no box and runs no `git commit`: the main agent lifts that block into `scripts/close-subtask.sh`, the one writer of the checkbox grammar |
| `tech-reviewer` | Correctness at technology boundaries (templates, SQL, APIs). Holds `Bash` for **measurement only** — never a mutation of files or git state — so a finding that rests on a runnable check carries the command and its output instead of an argument |
| `final-reviewer` | Fresh review of finished lean-route work for a beginner: reports each gap with the command that reproduces it, never edits |
| `auditor` | Compares built code against story + design; detects scope creep. Writes `.draft/audit-report.yaml` on the same before-the-summary contract; its `Write` reaches that one path and nothing else |

### Check reuse

A story runs the same validation command several times: the Executor's Validation, its Refactor re-run, the end-of-run gates, `epico-validate-run`, the Auditor's reproductions. `epico-check` runs a check and, once a project switches reuse on, returns the PASS of an identical earlier run — same command, same code, same environment — without running it again. Only a PASS is ever reused; a FAIL always runs.

| Command | Purpose |
|---|---|
| `epico-check run [--fresh] [--timeout <s>] -- <cmd>` | Run a check, or return its reused PASS; prints one JSON line |
| `epico-check lookup -- <cmd>` | Say what `run` would decide, running nothing |
| `epico-check stats` | Summarise the shadow log: runs, how many would have been reused, the time that saves, and every disagreement |
| `epico-check profile --detect` | Print a proposed profile from the manifests and ignored local files present; writes nothing |

Reuse is configured per project in `.epico/reuse-profile.json`, which `init` writes: `mode` is `off`, `shadow` or `on`, with `tools` (version probes whose output joins the key), `inputs` (gitignored files a check reads) and `never` (command substrings that always run). Every project starts in `shadow`, the default: every check runs and the log records whether a PASS would have been reused. Switch to `on` by hand once `epico-check stats` shows no disagreement traced to the key. The ledger lives in the git common directory, is shared by every worktree of the repository and is never committed. See [references/check-reuse.md](references/check-reuse.md).

### Automatic validation

When a story artifact is written to `.epico/stories/*/`, a PostToolUse hook runs `scripts/validate-story.sh` to check frontmatter, structure, and cross-references (R-numbers traceability). Archive directories are read-only — edits are blocked by a PreToolUse hook.

---

## Directory Layout

```
epico/
├── .claude-plugin/plugin.json   # manifest (name, userConfig, homepage, repository)
├── settings.json                # plugin defaults (subagentStatusLine)
├── skills/epico/SKILL.md         # main skill (/epico:epico)
├── agents/                      # 7 sub-agents: analyst, test-advisor, reviewer, executor, tech-reviewer, auditor, final-reviewer
├── hooks/hooks.json             # 4 hook events (PreToolUse, PostToolUse, SessionStart, SubagentStop); the guards fail closed
├── output-styles/epic.md        # optional structured output style
├── bin/                         # epico-* wrappers on PATH — Claude Code CLI only; a surface without a shell (claude.ai, Cowork) has none
├── references/                  # mode-specific operational guides
├── scripts/                     # bash validators, hook scripts and the epico-* tools
├── assets/examples/             # reference outputs for each scale
├── evals/                       # native eval suite (claude plugin eval)
├── tests/                       # bats unit tests for scripts
└── .github/workflows/           # shell-ci (shellcheck + bats + example validation + plugin validate --strict)
```

---

## Versioning policy for `.epico/`

**`/epico:epico init` asks once, per project, and records the answer.** There is no silent default in an interactive session — the question offers exactly two options and writes the state each one implies.

| Option | What init writes | Recorded in `.epico/.gitpolicy` |
|---|---|---|
| **Versioned artifacts** (recommended) | `.epico/.gitignore` with `.draft/`, `*.wip` and `node_modules/`; offers to remove a root-`.gitignore` rule that ignores `.epico/` — quoting the line, never silently | `tracked-md` |
| **Local-only** | `.epico/` appended to the root `.gitignore` | `local-only` |

Versioned tracks exactly `story.md`, `design.md`, `tasks.md`, `EPICO.md` and `archive/manifest.yaml`. **`.draft/` is never versioned under either policy** — it is scratch space: run logs, authored tests, phase snapshots, `*.wip`, and the story's evidence files (`deviations.yaml`, `red-evidence.yaml`, the validation and audit reports) — the last because their durable forms are the archive's summary and, where `ai-memory` is detected, the pages the orchestrator writes.

**Why it is a question and not a default.** Without a declared policy, lifecycle history gets lost: a track→untrack transition deletes stories from history, a squash leaves duplicates split across `stories/` and `archive/`, and a `.gitignore` stops matching what is actually committed. Versioning the `.md` artifacts and ignoring `.draft/` gives the most auditable lifecycle, so versioned is *recommended*; it is still *asked*, because each of those failures comes from a policy nobody said out loud.

**Non-interactive runs get local-only, without prompting.** A headless or Agent SDK `init` applies the conservative status quo and never starts committing `.epico` behind your back. It also never overrides a policy already recorded: a workspace that declares `tracked-md` is left exactly as it is.

**A per-project choice — init asks, and it supersedes any global doctrine.** If your global `CLAUDE.md` or personal convention says "never commit `.epico`", the answer recorded for *this* project wins here. Epico never reads or edits your global configuration.

**Checking the state:** `scripts/epico-gitpolicy.sh` is a read-only lint that prints one JSON object comparing the declared policy against what git actually does — `{git, policy, gitignore_ignores_epico, gitignore_source, tracked_md, tracked_draft, verdict}`, where `verdict` is `consistent`, `contradiction` or `partial`. Init runs it before asking, to show you the state you are choosing from.

```bash
bash "$EPICO_PLUGIN_ROOT/scripts/epico-gitpolicy.sh"   # from the workspace root
```

Full walkthrough of both branches: [references/init-mode.md](references/init-mode.md#versioning-policy).

---

## CI / Headless Usage

Run validation as a CI step without launching an interactive session:

```bash
EPICO_PLUGIN_ROOT=./epico  # path to cloned plugin
bash "$EPICO_PLUGIN_ROOT/scripts/validate-story.sh" .epico/stories/001-feature/ --cross-ref
```

Use `--strict` in CI gates for stories expected to be production-ready (promotes warnings to errors, exit 1 on any warning):

```bash
bash "$EPICO_PLUGIN_ROOT/scripts/validate-story.sh" .epico/stories/001-feature/ --cross-ref --strict
```

When the plugin is active, the scripts are also on PATH as `epico-validate`, `epico-xref`, `epico-archive`, `epico-doctor`, `epico-test-diff` and the other `epico-*` wrappers.

### What a story actually cost

Prefer Claude Code's own numbers. `/usage` shows the session's spend; a `claude -p --output-format json` run returns `modelUsage` and `total_cost_usd`; and OpenTelemetry splits tokens by main agent and sub-agent (`claude_code.token.usage`, attribute `query_source`) — start Claude Code with `CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=console OTEL_LOG_TOOL_DETAILS=1` and filter on `plugin.name=epic`.

For a session recorded without telemetry, `scripts/story-telemetry.sh` reads the transcript (and the sub-agent transcripts beside it) and reports what was spent — **in tokens and wall clock, never in money**. It writes no files and makes no network call. The transcript format is internal to Claude Code, so treat this as a fallback.

```bash
bash "$EPICO_PLUGIN_ROOT/scripts/story-telemetry.sh"                      # this project's latest session
bash "$EPICO_PLUGIN_ROOT/scripts/story-telemetry.sh" --since 2026-01-01T18:00:00Z   # one phase, by window
```

One JSON object on stdout: tokens split `main` / `subagent` (input, cache creation, cache read, output), models seen, wall clock, and `events` beside `unique_messages`.

Three things it deliberately does **not** do, each for a stated reason:

- **No dollars.** The transcript carries usage and no price. A price table shipped inside a plugin ages into a confident wrong answer; the reader knows the current prices.
- **No silent summing.** The transcript repeats a message's usage on every content block — so usage is summed per distinct `message.id`, and both counts are emitted so you can see that it happened.
- **No claim it cannot back.** `subagent_split_verified` is `false` until the run actually saw a sidechain event, so a zeroed `subagent` block reads as *none seen*, never as *confirmed none*.

Generate stories programmatically with the Agent SDK:

```bash
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude -p "/epico:epico Add retry logic to the payment gateway" \
  --plugin-dir /path/to/epico \
  --permission-mode acceptEdits --permission-prompts none \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Agent,mcp__ai-memory__*" \
  --output-format json
```

Never add `--bare`: it skips the plugin's hooks and sub-agents. See [references/ci-mode.md](references/ci-mode.md) for every recipe, the reason for each flag, and GitHub Actions examples.

### Running the eval suite

The `evals/` directory is a suite for Claude Code's native runner — 30 trigger cases and 6 end-to-end cases, each run in an isolated home:

```bash
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude plugin eval . --no-publish --scaffold --allow-tools Skill Bash Write Edit Agent
```

Always pass `--no-publish` (otherwise the report is published to claude.ai). Details and cheaper subsets: [evals/README.md](evals/README.md).

---

## Plugin Options

Configurable via the install wizard or directly through settings. Each option is non-sensitive. `aiMemory` and `defaultScale` reach the skill through `${user_config.KEY}`; hook processes receive every option as `CLAUDE_PLUGIN_OPTION_<KEY>`.

| Option | Default | Purpose |
|---|---|---|
| `defaultScale` | `standard` | Fallback mode when triage cannot settle the mode |
| `aiMemory` | `auto` | `auto` uses the ai-memory MCP server when it answers; `off` never calls it |
| `staleThresholdDays` | `7` | Days of inactivity before the story list flags a story with pending tasks |
| `spikeStaleThresholdDays` | `14` | Days of inactivity before a spike whose Verdict is still `open` is flagged — measured by its Verdict, not its checkboxes |

---

## Stale stories

The story list (`/epico:epico stories`) flags stories with pending tasks untouched for more than `staleThresholdDays` (7 by default) and spikes whose `## Verdict` is still `open` after `spikeStaleThresholdDays` (14 by default). It is a single pass run while you look at the list — nothing polls in the background.

---

## Output Style (optional)

Epico ships with a structured output style for Triage proposals, Phase Gates, Run reports, and validation/audit output. Activate it with:

```
/output-style epic
```

This is opt-in — no default behaviour changes. Defined in `output-styles/epic.md`. Declares `keep-coding-instructions: true`, so the style keeps Claude Code's own coding instructions in the main session. Sub-agents run their own system prompts, so no output style changes how they respond.

---

## Running in restricted environments

### `disableSkillShellExecution`

The `## Project State` block in `skills/epico/SKILL.md` uses inline shell execution (`!` prefix) to list existing stories, print the constitution header, and report git HEAD. When the managed setting `disableSkillShellExecution: true` is active, these commands are replaced with `[shell command execution disabled by policy]` and the skill renders without initial context.

The skill still functions — pass the missing context explicitly in the prompt:

```
/epico:epico Add password reset. Context: project already has stories 001 (signup), 002 (login).
```

See the [setting reference](https://code.claude.com/docs/en/settings#settings-files) for managed-settings deployment.

---

## Design Principles

- **Artifacts in English** — consistent quality across Claude models
- **EARS notation** — `SHALL`, one condition per requirement, each independently testable
- **Hierarchical traceability** — R-numbers flow from story → tasks → code
- **Test-first at every scale** — Standard and Full at `project`/`product` level author failing tests at plan time (Test Advisor, Phase 3); Fast, and any story at `experiment`/`tool` level, authors them at run time, single-author. A Fast sub-task without testable logic pins behavior via its `Acceptance` field instead
- **Fail fast** — executors stop on validation failure, never auto-fix silently
- **Draft recovery** — each phase approval saves `.draft/` inside the story directory ([never versioned under either policy](#versioning-policy-for-epic)) so interrupted sessions resume cleanly. Drafts live in the project, not in `${CLAUDE_PLUGIN_DATA}`, keeping them tied to the repo and visible to teammates inspecting the same checkout.
- **Numbers never recycled** — archived stories keep their numbers permanently

---

## Contributing

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the maintainer-facing
overview: pipeline, persistence layer, hook web, invariants, and
extension points.

## License

MIT — see [LICENSE](LICENSE).

## Author

[lucascouts](https://github.com/lucascouts) · lucascs@protonmail.com

## Version

0.27.1 — see [CHANGELOG](./CHANGELOG.md).
