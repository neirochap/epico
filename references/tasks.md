# Tasks Template

Use this template for the `tasks.md` file in all story types and scales.

## Contents

- [Template](#template)
- [Why the Scale Rose](#why-the-scale-rose)
- [The Declared Scale](#the-declared-scale)
- [Task Format Rules](#task-format-rules)
- [Rules](#rules)
- [Sequencing Guidelines](#sequencing-guidelines)
- [Gotchas](#gotchas)
- [Fast Scale Adaptations](#fast-scale-adaptations)
- [Spike Scale Adaptations](#spike-scale-adaptations)

## Template

```markdown
---
story: <story-name>
type: feature | bugfix
scale: fast | standard | full | spike
scale_reason: <one line — required whenever scale is not `fast`>
version: 1
created: <date>
---

# Implementation Plan - [Story Name]

## Overview

[2-3 sentences: implementation approach, sequencing strategy, and key dependencies.]

## Task List

- [ ] 1 - [Task Name]
  - _Complexity: [level] | Tests: [summary] | Risks: [summary] | Dependencies: [refs]_
  - Objective: [Clear coding goal — what this achieves]

  - [ ] 1.1 - [Sub-task Name]
    - _Complexity: [level]_
    - Context:
      - Files: `path/to/file` (reason to read)
      - Docs: <library>@<lockfile version> — <topic>
      - Research: "specific query" (brave-search)
    - Objective: [Concrete coding goal]
    - ToDo: [Technical approach — files to create/modify, patterns to follow]
    - Tests: [Type] · `path/to/test_file` — scenarios to cover
    - Validation: [Command or check that proves it works]
    - Requirements: R1.1, R2.3
    - Quality: Q2, Q5

  - [ ] 1.2 - [Another sub-task]
    - Objective: [...]
    - ToDo: [...]
    - Validation: [...]
    - Requirements: R1.2

  - Commit: "feat(NNN): description of what this group achieves"

- [ ] 2 - [Next Task]
  - _Complexity: [level] | Tests: [summary] | Risks: [summary] | Dependencies: Task 1_
  - Objective: [...]

  - [ ] 2.1 - [Sub-task]
    - [...]

## Quality Gates

- [ ] All acceptance criteria validated
- [ ] All task validations pass
- [ ] All tests written and passing
- [ ] Code integrated (no orphaned implementations)
- [ ] Error handling implemented
- [ ] Q2 — Lint: `<command>` exits 0
- [ ] Q5 — Unit tests: `<command>` green
```

## Why the Scale Rose

**`fast` is the floor, and rising above it costs a written reason.** `scale_reason:` holds it — one line, in the frontmatter, naming what in the request made the smaller shape insufficient. Absent at `fast`, expected at every other scale; validation warns when it is missing, never blocks.

The field exists because the scale moves a story's cost and duration more than any other triage decision, the engineering level included — and left unstated, it surfaces only in the recorded line, with the plan already written. **A decision that moves the bill more than the level does cannot be the one decision nobody states.**

A reason is not a justification ritual: "three integrated surfaces and a migration" is a reason; "the request is complex" is not, because it names nothing the reader can check.

## The Declared Scale

**`tasks.md` is authoritative for the declared `scale`.** It is the one artifact every scale has — a fast or spike story is tasks-only and can declare its scale nowhere else — so the value written here is the live one, never a leftover from an earlier shape of the work. Every tool that has to know how a story is shaped resolves the scale from here: validation, the archive preflight and the manifest entry it writes, the traceability cross-reference, and the staleness monitor.

A `story.md` declaring a different `scale` is **reported**, not honoured: validation warns, naming each artifact with the value it declares and the value actually in force, and then proceeds with the one `tasks.md` declares. It does not guess which of the two is stale — that is the author's call, so fix whichever artifact is wrong. The same holds for a `design.md`, which is read and checked and compared but never resolves: it describes the solution, not the shape of the work.

## Task Format Rules

### Structure

1. **Maximum 2 hierarchy levels.** Tasks (1, 2, 3) and sub-tasks (1.1, 1.2). No deeper nesting.
2. **Title format:** `- [ ] N - Task Name` — no bold wrappers, no classification prefix in the title.
3. **Metadata line:** First line after task title, always in italics (`_..._`). Contains only: Complexity, Tests, Risks, Dependencies. Pipe-separated.
4. **Sub-tasks inherit** parent metadata. Only declare fields that differ from the parent.
5. **Omit fields** that are not applicable or inherited unchanged. Never fill "None" in a sub-task if the parent already says "None".

### Checkbox Grammar

Every task, sub-task, and Quality Gate carries one of three boxes:

| Box | State | Meaning |
|---|---|---|
| `- [ ]` | open | still owed — the only state that counts as pending |
| `- [x]` | closed | the work was done |
| `- [~]` | closed without doing the work | must say why on the same line |

A `- [~]` box **MUST** carry a qualifier on the **same line**: a box closed without doing the work has to say why. Syntax: `- [~] N.N - Title (qualifier: reason)`.

| Qualifier | Meaning | Terminal? |
|---|---|---|
| `deferred: <reason>` | resolved in the plan, execution awaits an external actor (hardware, operator, live proof) | **no** — the story becomes `done-except-external` |
| `waived: <reason>` | gate consciously dispensed (tool absent, user decision) | **yes** |
| `n-a: <reason>` | not applicable by construction | **yes** |
| `superseded-by: NNN` | this sub-task's scope moved to story NNN | **yes** |

- The qualifier is mandatory. A `[~]` with none, or with an unrecognized one, is a **validation error** naming the line and the four valid forms.
- Matching is token-anchored: `(n-a: ...)` qualifies, the tail of a word like `man-a:` does not.
- If a line carries both `deferred:` and a terminal qualifier, **`deferred:` wins** — the work is still owed by someone.
- Implementing sub-tasks and Quality Gates use the same grammar. There is no per-line-type distinction.

#### Discharging a Deferral

A `deferred:` box is the **only** closed state that can reopen into `[x]`, and only through one call: `close-subtask.sh <story> <box> --fulfill "<evidence>"`. A terminal qualifier cannot. `waived:`, `n-a:` and `superseded-by:` record a decision already taken rather than work still owed, so overwriting one would erase the decision instead of discharging a debt — if the decision itself changed, that is a deliberate edit, not a close call.

The fulfilled line carries both halves, what discharged the debt and the debt it discharged:

```
- [x] N.N - Title (fulfilled: <evidence>; original deferral — <reason>)
```

**When the reason itself goes stale**, the box stays `[~]` and only its text changes: `close-subtask.sh <story> <box> --restate "<reason>"`. The debt is still owed — this says why it is owed *now* — so the census, the `status:` stamp and the group header are all untouched. It accepts the one state `--fulfill` accepts and refuses the same others, so it cannot tidy a decision away, and it is the only tool that can repair a `(deferred: )` carrying no reason at all.

**This paragraph is the shape's only home** — every other file cites it rather than repeating it. The dash spelling is required, not a matter of taste: the canonical qualifier regex `(^|[^[:alnum:]_-])deferred:`, shared by every script that reads this grammar in code, still matches the obvious `(was deferred: ...)`. Written that way, an `[x]` box would be read back as an outstanding deferral by every one of those readers and the story could never reach `done`. `original deferral —` carries no qualifier token at all, so it depends on no regex detail surviving.

### Completion

One definition, used by every mode that reads a task list:

- A story is **complete** when **no `[ ]` remains**.
- It is **`done`** when every box is `[x]` or terminal `[~]`.
- It is **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`.

`done-except-external` is a **computed condition** — derived from the boxes at read time, never written to a file.

Counting, for progress and reporting:

- `total` = every box, whatever its state (`[ ]`, `[x]`, `[~]`)
- `closed` = `[x]` + terminal `[~]`
- `deferred` = `[~]` qualified `deferred:`
- progress renders as `closed/total (+D deferred)` — the `+D` is omitted when `D` is 0

### Dependency Satisfaction

Whether a task may *start* is a different question from whether a story is *complete*, and conflating the two is how a deferred box turns into work built on nothing. One definition, used wherever a `Dependencies` field is read:

- A task is **satisfied** as a dependency when every one of its boxes is `[x]` or **terminal** `[~]` (`waived:`, `n-a:`, `superseded-by:`).
- A task closed as `[~] (deferred: …)` is **not** satisfied — the plan settled it, the world still owes the work.

This is the **strictest** of the places where terminal and deferred `[~]` part ways, not the only one. The two are interchangeable exactly where the question is *"is anything still owed by us?"* — **staleness**, where pending is `[ ]` and only `[ ]`, and the bare **complete** predicate, which asks only that no `[ ]` remains. They diverge wherever the question is whether the work actually happened: the **`closed` count** excludes deferred, **progress** renders it apart as `+D deferred`, **`done`** is blocked by it (a deferred box is not terminal), and, here, a **dependency** on it is not satisfied.

The asymmetry between the last two is real and intended: a story whose only non-`[x]` boxes are deferred is `done-except-external` — nothing here is pending — yet a task depending on one of those boxes must still wait, because the thing it needs does not exist yet.

### Authoring Ceiling

**A plan warns when it passes 32 KB.** That is the only threshold on the plan as a whole, and this paragraph is its only home: every consumer cites it rather than restating the number, so recalibrating it is one edit and not a hunt.

**There is no ceiling on the number of tasks**, per engineering level or otherwise. A pace of boxes per minute does not predict a run, and a box is not a unit of work — "create `.gitignore`" and "implement the collection module" are each one box. **How many tasks a story has is derived from the work, not from its level.** Industry practice agrees: a work breakdown structure bounds the *size of each work package* — the 8/80 rule, eight to eighty hours, and explicitly a heuristic rather than a requirement — and never the count; agile story splitting prescribes no number of sub-tasks at all, only that each slice be independently valuable and verifiable.

**The bound is on the unit instead.** A sub-task is **one Executor pass**: one objective, one set of files it may touch, and a `Validation:` command that can be run to prove it. A sub-task that cannot be validated on its own is too big, whatever the plan's total — and that is the question to ask, at any count. The number that follows is whatever the work requires.

The 32 KB threshold sits well above a typical healthy `tasks.md` (around 11 KB) and below the size at which a plan usually has to be split (around 50 KB and up).

The bytes warning is a **warning at every site, never a block**, and it makes two offers:

- **Cut** the scope — some of what is planned is not what was asked for
- **Split** the plan into waves — the scope is right and too big for one story

The two sites: **at Phase 3** the orchestrator makes the offers — interactively as a question, headless as a logged note that proceeds; **at validation** `validate-story.sh` warns, so a plan that shipped oversized stays visible afterwards and not only at the moment it was written. In batch create the warning surfaces in the approval block and the split is deferred to a post-batch create — the live interview is never re-entered. See [batch-create.md](batch-create.md).

A story that genuinely needs a large plan keeps it: the threshold asks the question, the author answers it.


### Metadata Line Fields

The metadata line appears on parent tasks and optionally on sub-tasks (only overridden fields).

| Field | Values | Required |
|---|---|---|
| Complexity | Trivial / Simple / Moderate / High | Always on parent |
| Tests | None / summary (e.g. "Unit", "Unit + Integration") | Always on parent |
| Risks | None / short description | Always on parent |
| Dependencies | None / Task references (e.g. "Task 1", "Task 2.3") | Always on parent |

### Content Fields

Content fields appear in sub-task bodies. Include only fields that are applicable.

| Field | When to include | Description |
|---|---|---|
| Context | Sub-task needs research before implementation | Files to read, Docs (MCP), Research (MCP) |
| Objective | Always | What this achieves (1 line) |
| ToDo | Always (implementing sub-tasks) | Steps to implement |
| Tests | Sub-task produces testable code (set by Test Advisor) | Type · `path` — scenarios to cover |
| Acceptance | Fast-mode sub-task without a `Tests` field | 1-3 observable-behavior statements |
| Validation | Always | Command or check proving completion |
| Requirements | Standard + Full scales | R1.1, R2.3 format. Omit for fast scale |
| Quality | When the story carries a `## Quality Requirements` legend — in story.md (Standard, Full) or at the top of tasks.md (Fast) | Q1, Q3 format — the legend lines this sub-task exercised ([quality-catalog.md](quality-catalog.md)) |
| Commit | Last sub-task of a group, or inline on single sub-tasks | Conventional commit message |

### Context Field

The Context field tells the implementer (human or agent) where to gather information before coding.

```markdown
- Context:
  - Files: `path/to/existing.go` (existing auth pattern)
  - Docs: github.com/golang-jwt/jwt/v5@v5.x — ParseWithClaims, validation options
  - Research: "Argon2id recommended parameters 2026" (brave-search)
```

- Only include sub-fields that apply. If only Docs is needed, omit Files and Research.
- Docs names the library, its version from the lockfile, and the topic — never a tool. The implementer follows the [Docs source order](mcp-integration.md#docs-source-order).
- A research MCP in parentheses is a suggestion based on servers detected during triage; several can be listed: `(brave-search or exa)`.

### Tests Field

Format: `Type · \`path/to/test_file\` — scenario1, scenario2, scenario3`

For an `E2E` sub-task the format carries the selected E2E tool as an explicit segment: `` E2E · `tool` · `path/to/test` — scenarios `` (for example `` E2E · `playwright` · `e2e/checkout.spec.ts` — scenarios ``). The `tool` segment is the story's selected E2E tool, read from the `## Tooling Decisions` block of `design.md` (the `E2E tool:` line, e.g. `playwright`).

- **Type is always explicit:** Unit, Integration, E2E — because test conventions vary across languages.
- **Path** uses the target language/framework test conventions.
- **Scenarios** are a concise comma-separated list of what to cover.
- When a sub-task's logic is already tested by another task: `Covered by Task X.Y`
- The Tests field is populated by the **Test Advisor** sub-agent (see SKILL.md), not by the main agent.
- A sub-task's Tests field never names the file of another sub-task's pre-authored test: `epico-test-diff` compares that file whole with its authored copy, so cases added to it block the other sub-task's close. Each test-first sub-task gets its own file; shared helpers go in a sourced file.

**Standard + Full scales at engineering level `project` or `product` — the Tests field is _authored_, not merely specified** ([engineering-level.md](engineering-level.md)). During Phase 3, the test-advisor writes the actual test file under the story's `.draft/authored-tests/` directory, mirroring the target test path (the `path` shown in the Tests field). A `Unit` or `Integration` test is authored as a failing test and Red-verified during Phase 3 — the test-advisor runs it to confirm it fails for the right reason and records that Red verification in `.draft/red-evidence.yaml`. An `E2E` test is authored at plan time too, using the story's selected E2E tool, but its Red-phase verification is **DEFERRED to Run mode** — it is not run during Phase 3 (E2E tests need the running application and an E2E environment Phase 3 does not set up); the test-advisor records a deferred-Red entry instead. The `path` in the Tests field is therefore the target location an executor will copy the authored test into — the test itself already exists in `.draft/authored-tests/` before implementation begins. **At `experiment` or `tool` level a Standard or Full story stages nothing:** the main agent decides the field with the Test Advisor Lite checklist ([phase-gates.md](phase-gates.md#test-advisor-lite-fast-mode)) and the test is written at run time, exactly as for Fast ([run-mode.md](run-mode.md#run-time-test-first-ordering)); at `experiment` the field is optional, as in a spike.

### Acceptance Field

Format: a bullet list of 1-3 observable-behavior statements, placed in the sub-task body alongside `Validation`.

```markdown
- Acceptance:
  - Loading a well-formed config file returns a populated config object
  - Loading a missing file returns a clear error, not a crash
```

- **Optional** — present only on sub-tasks that have no `Tests` field. A sub-task carries one or the other, never both.
- **Fast-only** — Standard and Full sub-tasks use the EARS R-number in their `Requirements` field as the anchor, so the `Acceptance` field does not exist there.
- **Sub-task-level** — never on a parent task, and never beside a group-level `Commit:` field (that field implements nothing).
- **EARS-lite** — plain statements of what is observably true, with no EARS `SHALL` ceremony. Describe the behavior, not how it is built.

### Commit Field

- **One `Commit:` field per task group**, written on the group itself, carrying the message the whole group commits under.
- **It is a field, never a checkbox.** A Commit checkbox is never the unit of work — it exists to carry a message — and as a box it leaves every group reading as partially open. That false-partial shape is the one this framework retired; `scripts/migrate-story.sh` converts the legacy form, message verbatim.
- A group with a single working sub-task may carry the field on that sub-task instead.
- **Dependency satisfaction reads the boxes that exist.** With no Commit box in the group, nothing waits on one: a dependency is satisfied by the boxes the plan actually declares.
- Commit messages follow conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`.
- **Story anchor (recommended).** Scope the subject with the story number — `type(NNN): subject`, e.g. `feat(012): add retry queue` — and name the branch `feat/NNN-slug`. These are the two anchors `scripts/story-git-status.sh` reads integration from (a merged `feat/NNN-*` branch, or a subject carrying `(NNN)` or `NNN-slug` as a delimited token); a commit with neither is invisible to it. Checked, not gated: `scripts/validate-story.sh` warns on any `Commit:` field whose subject carries no `type(NNN):` anchor for its own story number (zero-padded or not). A warning, never an error — a foreign commit convention stays usable, but drift is no longer silent.

### Generated Quality Gates

The five gates in the template are fixed. After them, the section carries **one or more boxes per line of the story's `## Quality Requirements` legend — one per target** ([quality-catalog.md](quality-catalog.md)), written as `- [ ] Qn — <item>: <command>` — the identifier, the item's name and the command that proves it, so the box settles by running the command and nothing else. They are generated from the legend when `tasks.md` is written, in legend order, and never hand-added: a gate with no legend line is a phantom, a legend line with no gate is a generation defect. Validate settles a generated gate by running its command ([validate-mode.md](validate-mode.md)); a layperson sees each as the check it ran, never by identifier ([plain-register.md](plain-register.md)).

### Complexity Guide

| Level | Signal | Examples |
|---|---|---|
| Trivial | Single command, config change, boilerplate | Create directory, install deps, add config |
| Simple | Straightforward logic, clear input/output, 1 file | CRUD function, simple validation |
| Moderate | Technical decisions, multiple files, edge cases | Auth middleware, pagination logic |
| High | Cross-cutting concerns, integrations, unknowns | External API integration, complex state |

## Rules

1. **Coding tasks only.** Exclude: deployment, documentation writing, UAT, performance metrics collection.
2. **Every sub-task references requirements** (standard and full scales). Use R1.1, R2.3 format. For bugfixes, reference Current/Expected/Unchanged behavior items. For fast scale, omit this field.
3. **Checkboxes on all items.** The grammar is `- [ ]` open, `- [x]` done, `- [~]` closed without doing the work — and a `- [~]` always carries a same-line qualifier (`deferred:`, `waived:`, `n-a:`, `superseded-by:`). See Checkbox Grammar above.
4. **Dependencies are explicit.** If task 2 requires task 1, the metadata line says so. Sub-task dependencies reference parent.task format (e.g. "Task 1.2").
5. **Validation is testable.** "Works correctly" is not acceptable. "`go test ./models/...` passes" is.
6. **Quality Gates are mandatory.** Always include the quality gates section at the end.
7. **Traceability.** After generating tasks, the skill cross-references every requirement with tasks (standard and full scales). Every requirement must appear in at least one sub-task's Requirements field.
8. **Quality Gate coverage.** Every item in Quality Gates must be addressed by at least one task. No gate should exist without a corresponding task or validation.
9. **Task granularity.** Do not split tasks that affect the same file or that represent sequential steps with no independent verification point between them. Each sub-task should represent a meaningful, independently verifiable unit of work.
10. **Commit coverage.** Every task group must have a Commit field (either as sub-task or inline). No implemented code should remain uncommitted.
11. **Error propagation in ToDo fields.** When a ToDo describes calling a function, method, or service that can fail (returns error, throws exception, returns nullable/optional), the ToDo must explicitly state how the error is handled. Write "call X and return 500 on error" or "call X, on failure re-render with error message" — never just "call X". This applies to all internal calls (store, service, repository, external API), not just user-facing operations.

12. **Quality coverage.** Every line of the story's `## Quality Requirements` legend ([quality-catalog.md](quality-catalog.md)) is cited by at least one sub-task's `Quality:` field, and the Quality Gates section carries one generated box per line (see Generated Quality Gates). `cross-reference.sh` reports an uncited line as a quality orphan and a cited-but-undeclared identifier as a phantom, and exits 1 on either.

13. **Failure cases, one test each.** A sub-task whose `Tests` field covers a rule about bad input, end of input, a data file or a floor case names those cases in the field — one test per failure case, never one test for "the errors". The cases are what a run forgets first, and a named case is one the close can count.

## Sequencing Guidelines

- Order tasks so each one builds on the previous
- Group related sub-tasks into tasks by component or feature area
- Place infrastructure/setup tasks before feature tasks
- Place integration tasks after the components they integrate
- **Interface verification tasks:** When design.md defines components that exchange data (producer→consumer), the last task group before the final wiring/main task must include a sub-task that verifies the data contract between them. This is not a test — it's a verification that the producer's output structure matches what the consumer expects. Examples: handler data struct contains all fields referenced by the view template; API response type matches the client's expected type; event payload contains all fields the listener reads. This sub-task catches integration mismatches before they reach the final assembly step.

## Gotchas

- Title format: `- [ ] N - Name` — no bold wrappers, no [T1] prefix
- A `[~]` box without a same-line qualifier is a validation error — closing a box without doing the work must say why
- Complete means no `[ ]` remains — not "every box is `[x]`"
- Maximum 2 hierarchy levels (task 1. + sub-task 1.1)
- Coding-only — no deploy, docs, UAT, performance metrics
- Each sub-task references requirement numbers (R1.1, R2.3) — except fast scale
- Metadata line in italics on parent tasks (Complexity, Tests, Risks, Dependencies)
- Tests field is populated by the Test Advisor, not the main agent (standard + full)
- Every task group must have a Commit field (inline or as sub-task)
- Sub-tasks inherit parent metadata — only override what differs
- A `Quality:` field cites legend lines (`Q2, Q5`); a generated gate carries its command; neither is hand-numbered outside the legend
- `engineering:` in the frontmatter is one of `experiment`, `tool`, `project`, `product`; `tasks.md` is authoritative for it, as for `scale:`, and what the level buys is read from it ([engineering-level.md](engineering-level.md))
- `requester:` in the frontmatter is `layperson` or `developer` — the level triage read, written at every scale. `hook-legend-guard.sh` reads it from the newest live story to decide whether a turn's process words owe a legend
- `run-model:` in the frontmatter, when present, is one of `sonnet`, `opus`, `haiku` — the model the user chose at clarify to run the story ([clarify.md](clarify.md#the-run-model-standard-and-full)). Absent, the run uses the session it is given
- `roadmap:` in the frontmatter, when present, lists the ROADMAP task IDs the story works on as a flow list, `roadmap: [2.4.1, 2.4.2]` ([clarify.md](clarify.md#the-roadmap-tasks-only-when-the-project-numbers-them)). `validate-story.sh` warns on a malformed list or an ID no ROADMAP or stage file holds; it never blocks

## Fast Scale Adaptations

When generating tasks for fast scale (no story.md):
- Omit `Requirements` field (no requirements to reference)
- Keep the same structure otherwise (metadata line, content fields)
- Quality Gates section is still mandatory
- **The legend lives at the top of `tasks.md`** — a `## Quality Requirements` section before `## Task List`, since Fast has no story.md ([quality-catalog.md](quality-catalog.md)); sub-tasks cite it in `Quality:` and the generated gates follow it like any scale
- At engineering level `experiment` the legend reads `none` — the proof is that it runs ([engineering-level.md](engineering-level.md)); the section is still present, no gate is generated from it, and the five fixed gates stay
- **Test-or-Acceptance contract rule:** every implementing sub-task carries either a `Tests` field or an `Acceptance` field — a sub-task with testable logic gets a `Tests` field, a structural sub-task with no testable logic gets an `Acceptance` field. A group-level `Commit:` field is exempt (it implements nothing).
- If during generation the scope appears larger than expected, recommend upgrading to standard scale

## Spike Scale Adaptations

A **spike** is a time-boxed probe: it exists to answer a question, and its deliverable is the answer, not shipped code. When generating tasks for spike scale (`tasks.md` only — no story.md, no design.md, no `.draft/`):

- Declare `scale: spike` in the frontmatter. It is the only place a spike can declare it — there is no other artifact — and that declaration is the authoritative one, exactly as it is for every other scale (see [The Declared Scale](#the-declared-scale)).
- **No requirements chain.** Omit the `Requirements` field and write no R-number anywhere in the file. With no story.md, an `R1.1` here points at nothing — it is a dangling pointer, not traceability, and validation treats any `Requirements:` field or R-token in a spike as an error. When traceability is what the work needs, promote the spike to a story instead.
- **Single-author**, like fast scale: no Test Advisor, no sub-agents, no drafts, no phase gate.
- `Tests` and `Acceptance` are **optional** here (unlike fast scale, where one of the two is mandatory): probe code is throwaway and the Verdict is the deliverable. `Validation` stays required on every sub-task — a probe step must still say what would show it ran.
- Keep the same structure otherwise (metadata line, content fields). The Quality Gates section is still mandatory; for a spike the gates are about the probe concluding, e.g. `- [ ] Verdict recorded (status no longer open)`.
- **A `## Verdict` section is mandatory** — a spike without a conclusion is a leak. See the template below.
- Scope the probe to something that can be concluded. A Verdict left `open` has a deadline of its own and LIST says so once it passes — the deadline is the `spikeStaleThresholdDays` option (14 days by default), applied in [list-mode.md](list-mode.md#spike-lifecycle); a spike that never concludes is the failure mode this scale exists to prevent.
- If the probe turns out to be a feature, do not grow the spike: record `status: promote` and let the follow-up story carry the work. Setting it in an interactive session gets you the offer to create that story pre-filled with the `conclusion:` — see [list-mode.md](list-mode.md#spike-lifecycle) for the handoff and for what makes a spike archivable.

**Verdict template** — the last section of a spike's `tasks.md`:

```markdown
## Verdict
- status: open
- conclusion: <1-5 lines: what was learned>
- promoted-to: NNN   # required when status: promote
```

The grammar below is what the shipped parser (`parse_verdict`, shared verbatim by `scripts/epico-index.sh`, `scripts/archive-story.sh` and `scripts/validate-story.sh`) actually accepts. It is fail-closed by design: anything it cannot read counts as not recorded.

- **Heading:** two or more `#`, then the word `Verdict`. Anything after it must be separated by a space — `## Verdict — cache probe` matches, `## Verdict:` does not, and a heading that does not match leaves the section invisible.
- **Where the section ends:** at the next `##`-or-deeper heading. Put the Verdict last so nothing truncates it.
- **`status:`** carries exactly **one** value — `open`, `promote`, or `wont-do`. Only the first `status:` line inside the section is read, and the value is cut at the first space or `|`, so a copy-pasted `open | promote | wont-do` reads silently as `open`. Write the value that is true.
- **`promoted-to:`** must start with a digit (`012`, `12`). The literal `NNN` is rejected on purpose: an unreplaced placeholder counts as **no target recorded**, and `status: promote` with no recorded target is a validation error. A trailing `# comment` after the number is fine.
- **`conclusion:`** is prose for a human; nothing parses it. Write what was learned, not what was done — it is what pre-fills the follow-up story on promote.
- Terminal states are `promote` (with a recorded `promoted-to:`) and `wont-do`; both make the spike archivable. `open` is not terminal.
