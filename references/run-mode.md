# Run Mode

Triggered by `/epico:epico stories run NNN`, `/epico:epico stories NNN run all`, or `/epico:epico stories NNN run N`.

## Contents

- [Procedure](#procedure)
- [Execution Flags](#execution-flags)
- [Tech Stack Detection](#tech-stack-detection)
- [Execution Threshold](#execution-threshold)
- [Task Execution Flow](#task-execution-flow)
- [Executor Sub-agent](#executor-sub-agent)
- [Multi-Tech Review](#multi-tech-review)
- [Context Passing Between Tasks](#context-passing-between-tasks)
- [Parallel Execution](#parallel-execution)
- [Run Mode Rules](#run-mode-rules)
- [Progress Tracking](#progress-tracking)
- [Handling Missing Tasks for Quality Gates](#handling-missing-tasks-for-quality-gates)

## Procedure

1. **Resolve story** — find `.epico/stories/NNN-*/`
2. **Read tasks.md** — parse all tasks, sub-tasks, and their fields
3. **Determine scope:**
   - `run NNN` or `NNN run all` → all pending tasks (those with `[ ]` — a `[~]` box is closed and is never pending)
   - `NNN run N` → specific task N and all its pending sub-tasks
   - `NNN run N.N` → specific sub-task only
4. **Check dependencies** — if a pending task depends on a task that is not **satisfied**, warn the user. Satisfied is defined once, in [tasks.md](tasks.md#dependency-satisfaction): every box `[x]` or terminal `[~]`, and a `[~] (deferred: …)` dependency is **not** satisfied
5. **Detect parallel groups** — identify non-blocking tasks (see [run-parallel.md](run-parallel.md))
6. **Tech stack detection** — scan tasks to build tech profiles (see Tech Stack Detection)
6a. **Recall prior deviations (when memory is available)** — one `memory_query` per run, `deviation OR discovery OR gotcha` plus the tech names from step 6, `limit: 10`. The hits go into every Executor's Project State beside this run's own register, as leads to verify. Absent memory, nothing is added ([mcp-integration.md](mcp-integration.md#memory-mcp))
7. **Materialize pre-authored tests (Standard/Full at engineering level `project` or `product` only)** — before any task execution, copy every file under the story's `.draft/authored-tests/**` into the real test tree at its mirrored path. This step is **idempotent**: if a target test path already exists in the real tree, **skip that file and emit a warning** (it may already exist from a prior Run, a partial `run N.N`, or a manual executor edit — never overwrite it). Files that do not yet exist are copied. Materialization runs once per Run, ahead of step 8. This step applies to **Standard and Full scales at `project` or `product` level only** — they are the ones that stage Test Advisor-authored tests in `.draft/authored-tests/` ([engineering-level.md](engineering-level.md)). **Fast and spike have no `.draft/`, and an `experiment` or `tool` story at any scale stages no test in it**, so such a Run has nothing to materialize and skips this step: Fast writes its tests at run time straight into the real test tree (see Task Execution Flow), and a spike is tasks-only by contract — `tasks.md` and nothing else ([tasks.md](tasks.md#spike-scale-adaptations)). Materialization only **copies** files — it never runs them. A materialized E2E test whose `.draft/red-evidence.yaml` entry carries `red_deferred: true` has its Red confirmed at task-execution time, not here (see Deferred Red for E2E sub-tasks under Task Execution Flow).

   **Materialization also checks the converse, because copying what exists cannot see what is absent.** Before copying, cross the pending task list against `.draft/`: a sub-task whose `Tests:` field is **not `None`** and which has **neither** a file under `.draft/authored-tests/` **nor** an entry in `.draft/red-evidence.yaml` never went through Phase 3 — except a `Unit` sub-task of a **Standard** story, whose test the Executor writes at run time by design. **Do not execute it — stop and report it by number**, then offer to author it now via the Test Advisor (the same one-sub-task flow [refine-mode.md](refine-mode.md#red-evidence-for-added-sub-tasks) defines) or to proceed with the sub-task's `Tests:` field explicitly waived and the waiver recorded in `.draft/deviations.yaml`. Running it as if it were test-first is the one option that is not available: the Executor would be handed a test-first sub-task with no test, and its conditional step 5 would branch on a premise that is false. **The usual cause is a refinement that added the sub-task after Phase 3 ran**, which is why the producing side is fixed there and this is the guard rather than the fix — one end of the wire is not a wire. **Fast and spike are exempt from this check exactly as they are from the copy** — and so is a Standard or Full story at engineering level `experiment` or `tool`, whose tests are written at run time by decision ([engineering-level.md](engineering-level.md)): none of them has authored tests for the cross to read, so the absence it hunts for is their normal state and never evidence of a skipped Phase 3. The exemption is load-bearing for a spike, whose `Tests` field is **optional but permitted** ([tasks.md](tasks.md#spike-scale-adaptations)) — a spike sub-task that does carry `Tests:` would otherwise be refused execution here by a guard about a phase a spike never runs.
7a. **Check the run model** — when `tasks.md` carries `run-model:` and this session runs on a different model, say so in one line before the plan — the story was planned to run on `<run-model>`; `/model <run-model>` switches this session — and go on: the line informs, it never blocks, and the user's choice of session stands. Absent the field, there is nothing to check ([clarify.md](clarify.md#the-run-model-standard-and-full))
8. **Present execution plan** — open with **the recorded line** — scale, requester level, engineering level with its expected multiple, and the plan size in Task List boxes, e.g. `standard · developer · tool (2–3×) · 11 boxes` ([engineering-level.md](engineering-level.md#where-it-is-recorded)) — then show which tasks will be executed, in order, highlighting parallel groups and executor assignment. A parallel group is **stated, not asked**: it runs as a group unless `--serial` was passed (see Parallel Execution)
9. **Wait for user confirmation** before executing

## Execution Flags

Parse flags from `$ARGUMENTS` after the run command:

| Flag | Behavior |
|---|---|
| (default) | Standard and Full: gate after every task group. **Fast runs as `--auto`**: it stops on a validation or test failure and on a doubt the constitution defaults do not cover, and nowhere else — a Fast story is small enough to see whole at the end, and a per-group gate would spend one round of the question budget on "go on" |
| `--auto` | Only stop on a failure. Group gates, doubts the constitution covers, doubts it does not, and the end-of-run question take the recommended option, each logged as an assumption (see [Assumptions under `--auto`](run-end.md#assumptions-under---auto)) |
| `--step` | Gate after every task group in a Fast run — the one way to ask a Fast story for its stops back |
| `--batch=N` | Gate every N task groups |
| `--gate=commit` | Gate only where a group's `Commit:` field is executed |
| `--serial` | Run every task and sub-task in order, including the ones detection proved independent — for a run that must read as a sequence |

Examples:
```
/epico:epico stories run 004                    ← default (gate after each group)
/epico:epico stories run 004 --auto             ← only stop on failure (a Fast story's default)
/epico:epico stories run 004 --step             ← a Fast run that gates after each group
/epico:epico stories run 004 --batch=3          ← gate every 3 groups
/epico:epico stories run 004 --gate=commit      ← gate only at commits
/epico:epico stories run 004 --serial           ← no parallel groups, whatever detection finds
```

## Tech Stack Detection

Before executing any sub-task, the orchestrator detects the technologies involved by scanning:

1. The sub-task's Context, ToDo, and Objective fields for tech references
2. File extensions mentioned in ToDo (`.rs`, `.html`, `.py`, `.ts`, `.go`, `.java`, etc.)
3. Libraries/frameworks mentioned (actix-web, Tera, Django, React, Express, Spring, etc.)
4. The project's manifest file (Cargo.toml, package.json, requirements.txt, go.mod, pom.xml, etc.)

This produces a `tech_profile` for the sub-task:

```yaml
tech_profile:
  language: Rust
  frameworks: [actix-web]
  template_engines: [Tera]
  databases: [SQLite/sqlx]
  key_libraries: [jsonwebtoken, argon2]
  boundaries:             # where different technologies interact
    - handler → template  # server code passes data to template engine
    - handler → database  # application code executes SQL
```

The `tech_profile` is passed to the Executor sub-agent prompt. Boundaries trigger Tech Review after execution, on every route.

**Each detected language maps to its section of [language-rules.md](language-rules.md)** — the secure-coding rules a linter does not catch — and only those sections are read, never the whole file. A detected language with no section there names none: say so in one line — `no language-rules.md section for <language>` — without inventing rules for it.

## Execution Threshold

**The route is chosen per sub-task, and it is not read off `Complexity`.** `Complexity` is a parent-task field — [tasks.md](tasks.md#metadata-line-fields) makes it *Always on parent* and merely optional on the sub-task — so routing on it alone sends every sub-task of a `Moderate` parent to a sub-agent. That is the expensive mistake: a sub-agent starts with an empty context and has to re-read what the orchestrator is already holding, so delegating work the orchestrator could do buys isolation nobody needed and pays for it in rediscovery.

**The question is whether the work needs what is in the context window.** A sub-agent starts blind to the conversation — the requester's answers, the decisions taken, what the earlier sub-tasks found — so it gets only work that needs none of it: a test written from the spec, a disposable probe, a review whose value is the fresh eye. Work that needs that context — production code above all — runs **inline**, or in a **new session** when the window is too full to carry it (the `degraded` band in Run Mode Rules); never in a sub-agent. The one exception is a parallel group, where several authors at once is the point and one main agent cannot be several. **In doubt, inline**: a sub-agent missing a decision fails silently, the main agent does not.

Read the sub-task's own body and take the **first** route that matches.

**A sub-task too vague to act on takes no route.** When it has **no ToDo and no runnable `Validation` command**, nothing says what to change and nothing could prove it changed: treat it as `failed` before routing — change no file, spawn nothing, and report it by number with an offer to refine the story. Neither the main agent nor an Executor invents the scope from the title. The Executor carries the same check as a backstop ([executor.md](../agents/executor.md)).

| The sub-task is… | How you can tell, from its body | Route | Why |
|---|---|---|---|
| **Verification** | its Objective is to review, audit or validate work that is already done | **Sub-agent, always** | here the fresh context *is* the product — whoever did not watch the author work is the only one who can see what the author cannot |
| **Parallel group member** | [run-parallel.md](run-parallel.md) proved it independent of its group and `--serial` was not passed | **Executor sub-agent, in a worktree when one is available** | several sub-tasks written at once need several authors; this is the only route on which an Executor writes production code |
| **Context-free** | it writes only a test from the spec, or a disposable file — a probe, a fixture, a generated report — or only reads, and nothing in it depends on the conversation | **Sub-agent** | it needs nothing the main agent holds, and its reading dies with it instead of settling into the orchestrator's context |
| anything else | production code, or any work that depends on an answer, a decision or a finding from this session — however many `Context` files it lists | **Main agent, inline** — or a new session when the band is `degraded` | the rule above; this row also takes every sub-task the rows before it do not clearly claim |

`Complexity` still governs the three columns the route does not decide. A sub-task carrying its own `Complexity` override uses that value; otherwise it inherits the parent's:

| Task Complexity | Tech Review | Context Gathering | Executor `effort` | Executor `model` under `by-complexity` |
|-----------------|-------------|-------------------|-------------------|----------------------------------------|
| Trivial | No | Optional | `low` | `haiku` |
| Simple | Only if multi-tech boundary | Required if Context field exists | `medium` | `haiku` |
| Moderate | Yes, if multi-tech boundary | Required | (omit — the agent's own `high`) | (omit — the session's model) |
| High | Always (even single-tech) | Required + extra research | (omit — the agent's own `high`) | (omit — the session's model) |

**This skill asks for the `effort` column**, so pass it as the Agent call's `effort` parameter when the row names one; omit the parameter otherwise, and the agent runs at its definition's `high`. A small sub-task does not need the depth of reasoning a design-level one does, and the per-spawn value is what lets one agent definition serve both. **The Executor's model is the user's choice, read from the `executorModel` plugin option** (SKILL.md, *Plugin options*): `inherit` — omit `model`, the Executor runs on the session's model; `haiku` — pass `model: "haiku"` on every Executor spawn; `by-complexity` — pass it where the last column says `haiku`, omit it otherwise. A Haiku Executor costs about a third less and takes longer under a Sonnet session — a trade the user makes, so it is offered, never imposed. It reaches production code only through a parallel group: everywhere else production code is inline, on the session's model. The Auditor and the Tech Reviewer take the **`reviewModel`** option the same way — `inherit` omits `model`, `sonnet` or `haiku` passes it. `inherit` is the default because a smaller reviewer is shallower: on the same code, a Sonnet review found 5 of 9 real defects where an Opus review found 8, and saved a fifth of the time. Never pass `model` on any other spawn.

**The route never relaxes the protocol.** Inline means the main agent runs the same six steps an Executor would (see Inline Route — Main Agent), gathers context whenever a Context field exists, and closes the box through `close-subtask.sh` like everyone else. It is the same work done in a cheaper place — never less work.

For `--auto` flag: routing unchanged. Sub-agents still run wherever the table sends them, but gates between tasks are removed (only stop on failure). A Fast story without the flag keeps its one extra stop — a doubt the constitution does not cover.

## Task Execution Flow

For each pending sub-task, in order:

### Run-time test-first ordering

**Two scales and two engineering levels land here, and for the same reason: nothing about their tests exists before the run starts.** Fast and spike are the single-author scales, with no `.draft/` at all; a Standard or Full story at engineering level `experiment` or `tool` skips the Test Advisor by decision ([engineering-level.md](engineering-level.md)) and keeps its `.draft/` for everything else. That is what makes the ordering below a *run-time* one. Standard and Full at `project` or `product` stage their tests at plan time and are unaffected by everything in this section.

For a sub-task of any of them carrying a `Tests` field, the test is authored, run, and confirmed failing **before** implementation begins — the order is **author → Red → Green → Refactor**:

1. **Author** the test from the sub-task's `Tests` field, Objective, and Acceptance contract.
2. **Run** it against a stub and confirm **Red** — first write the API's signatures where the implementation will live, each returning its type's zero value, then run the test: it must reach an assertion and fail there. A failure before any assertion (syntax error, wrong import, missing module, misconfigured runner) is `setup`, **not** valid Red; correct the test or the stub, then re-run, before implementation proceeds.
3. **Green** — implement until the test passes and the Validation command passes.
4. **Refactor** — improve the code while keeping the test and Validation green; revert any refactor that breaks either.

None of them authors tests at plan time — there is no Test Advisor sub-agent, no `.draft/authored-tests/`, and no `red-evidence.yaml`. Test authorship is done by the **main agent** at run time (the `test-advisor` sub-agent is not spawned), and the authored test is written **directly into the project's real test tree** — no `.draft/` staging, which is why step 7 (Materialize pre-authored tests) does not apply to any of them. Red confirmation lives in the run report only; it is not persisted to a file. **For a `layperson` requester it lives there and nowhere else — and what keeps it there is form, not vocabulary: between tool calls, a build turn writes nothing to the chat.** Each step's note — the test authored, its Red and why it was valid, the Green — is collected as it happens and written into `run-report.md` **once, at the end of the turn**: `epico-run-report --story <dir>` writes the skeleton — the recorded line, one line per closed box, the gates, the commits — and one `Edit` adds the notes no file holds, not an `Edit` per step, and not announced in the chat. The turn's only visible text is its closing three lines — and, on the turn that finishes the run, the next-step question after them ([End of Run](run-end.md#end-of-run--next-step-index)). A vocabulary rule alone does not hold this line — forbidden words leak in the interstitial text, never in the closing message ([plain-register.md](plain-register.md#ceiling-per-turn)); the form rule is what removes the place they leak into. This mirrors the "Plan time vs run time" note in `phase-gates.md` — the Test Advisor Lite checklist decides *whether* a test is needed; this section is *when* the test-first ordering happens.

A sub-task with no `Tests` field is implemented against its `Acceptance` field plus the Validation command — no test is authored. **The two scales differ in what may be absent**: Fast requires one of `Tests` or `Acceptance` on every implementing sub-task, while a spike may carry neither ([tasks.md](tasks.md#spike-scale-adaptations)) — probe code is throwaway and the Verdict is the deliverable. A spike sub-task carrying only `Validation` is therefore well-formed, and is implemented against that alone. A Standard or Full story at `experiment` or `tool` anchors a structural sub-task on its `Requirements` field with `Tests: None`, and at `experiment` may omit the field, like a spike.

**Unexpected green (every run-time test).** If a test authored at run time **passes on its first run**, the sub-task is blocked — the test is not establishing Red. Revise the test **once** so it fails for the expected reason. If it still passes after that single revision, **escalate to the user** rather than proceed — describe the test, the sub-task, and why it will not fail. Never weaken or delete assertions to force a failure. This is lighter than the Standard/Full 2-attempt cap.

The two routes below — inline and delegated — apply this ordering; Standard/Full sub-tasks at `project` or `product` are unaffected.

### Inline Route — Main Agent

The main agent executes directly but MUST follow the same step sequence as the Executor. No step may be skipped. The Executor's breaker holds here too: the same command failing three times ends the sub-task as failed, with the shared error as its reason. If a Context field exists, context MUST be gathered before implementation. **A server the sub-task starts is waited for with `epico-wait-port <port>`**, never `sleep N` and a retried `curl`: it returns the moment the port answers, or fails at its timeout. Started in the background, pass its pid — `epico-wait-port <port> --pid $!` — so a server that dies at boot ends the wait at once instead of costing the whole timeout. The validation commands run with `epico-check run -- <cmd>` ([check-reuse.md](check-reuse.md)). **The main agent reads the `language-rules.md` sections of the detected languages before implementing** — the same sections an Executor's prompt would name, because the inline route never loads the Executor's definition and would otherwise skip them.

**Tech review applies on this route too.** It is an orchestrator step, not an Executor step, so "the same step sequence" does not carry it: after the sub-task's validation passes and before the box is closed, run the Delegated Route's step 5 — spawn Tech Reviewers when the Complexity table in Execution Threshold calls for one. Production code that crosses a technology boundary is exactly where a generalist implementer misses what the reviewer catches, and routing it inline must not also drop its review.

For an **inline-routed** sub-task under the run-time ordering above (Fast, spike, or an `experiment`/`tool` story, `Tests` present), the main agent is the **single author** for the whole cycle: it authors the test, runs it, confirms **Red** (for the right reason), then implements inline to **Green**, validates, and **Refactors** — all in the one inline execution. The unexpected-green rule above applies: revise once, then escalate.

**The box is closed the same way it is on the Executor path** — one `close-subtask.sh` invocation, never a hand edit (see Closing a Box). Being the single author makes the main agent the executor here; it does not make it a second writer of the checkbox grammar. It produces the same closing block for itself that an Executor would have reported, and feeds it to the same script.

### Delegated Route — Executor Sub-agent

**A serial sub-task that writes production code never lands here** — it is inline (Execution Threshold). This route carries a parallel group's members and the sub-tasks that write only tests or disposable files.

Spawn an Executor sub-agent with the prompt defined in the Executor Sub-agent section. The orchestrator:

1. Builds the Executor prompt with task fields + story context + design interfaces + tech profile + the `language-rules.md` section of each detected language
2. Spawns the Executor — `run_in_background: false`, result awaited; with `isolation: "worktree"` for parallel tasks, a parallel group being several Agent calls in one message, every one awaited before the next step ([personas.md](personas.md#personas))
3. Waits for the Executor to complete
4. Reads the Executor's structured report
5. If PASS: check for tech boundaries → spawn Tech Reviewers if needed
6. If FAIL — the report's closing block carries `outcome: failed`: report to user, ask how to proceed. **No close call is made**: the box stays `[ ]` and nothing is written
7. After all reviews pass: **close the box** — one invocation of `close-subtask.sh` carrying the report's closing block (see Closing a Box). The orchestrator never edits the checkbox itself, and never re-reads tasks.md afterwards: the census and the status transition come back inside the script's JSON

For a **delegated** sub-task under the run-time ordering above (Fast, spike, or an `experiment`/`tool` story, `Tests` present), the test-first cycle is **split** between the orchestrator and the Executor — but the Executor protocol itself is **reused unchanged**:

- **Before spawning the Executor**, the orchestrator (main agent) authors the test, runs it, and confirms **Red** (for the right reason). The unexpected-green rule above applies: revise once, then escalate to the user. The test is written directly into the project's real test tree — none of them stages tests in `.draft/`.
- The orchestrator then passes that confirmed-failing test to the Executor as the read-only **"Pre-Authored Test"** input (its path and contents in the Executor prompt section of the same name). The Executor consumes it exactly like a materialized Standard/Full pre-authored test.
- The Executor runs the **existing six-step protocol with its conditional step 5** (see Executor Sub-agent): step 2 becomes Implementation (Green) — make the pre-authored test pass — and step 5 becomes Refactor. No new or scale-specific Executor protocol is introduced.

### Closing a Box

**Every `[x]` and every `[~]` this engine writes is written by one script.** The orchestrator does not edit a checkbox: not after an Executor, not on the inline route, not when settling a Quality Gate, and never inside a worktree.

```
epico-close <NNN|story-dir> <N.N|N|gate:<text-prefix>> \
  [--tilde "<qualifier>: <reason>"]
```

**One box per invocation of the script; several per call of the wrapper** — `epico-close <story> 2.1 2.2 2.3` closes them in order, one JSON object each, and stops at the first refusal; a flag (`--tilde`) takes one box. The story number (`010`) works in place of the directory — it resolves against the nearest `.epico/`. The box is named the way the grammar names it: a sub-task (`3.1`), a task group (`3`), or a Quality Gate by a **prefix of its own text** (`gate:All task validations`) — gates carry no number, so a prefix is how one is pointed at.

#### From the closing block to the call

The Executor's step-6 report ends with a machine-liftable **closing block** (defined in [executor.md](../agents/executor.md)); on the inline route the main agent produces the same block for itself. Lift the arguments from it and change nothing on the way:

| Closing block `outcome` | The call |
|---|---|
| `done` | `close-subtask.sh <story> <task>` — a plain `[x]` |
| `close-tilde` | `close-subtask.sh <story> <task> --tilde "<qualifier>: <reason>"` — a `[~]`, closed **without** the work being done |
| `fulfill` | `close-subtask.sh <story> <task> --fulfill "<evidence>"` — an outstanding `[~] (deferred: …)` becomes `[x]`, carrying both the debt and its discharge ([tasks.md](tasks.md#discharging-a-deferral)) |
| `restate` | `close-subtask.sh <story> <task> --restate "<reason>"` — the box stays `[~] (deferred: …)`, its reason is replaced ([tasks.md](tasks.md#discharging-a-deferral)) |
| `failed` | **no call at all** |

`<qualifier>` is one of the four the grammar defines — `deferred:`, `waived:`, `n-a:`, `superseded-by:` ([tasks.md](tasks.md#checkbox-grammar)) — and the reason is passed through verbatim, into the file rather than into the report.

**Neither `fulfill` nor `restate` is an Executor outcome.** The closing-block enum stays `done` / `close-tilde` / `failed`: an Executor closes a box it just worked, and a deferral is by definition work it could not do. The orchestrator makes this call later, when the external actor the deferral named has finally acted and the evidence exists. `restate` is the same shape of call for the case where the deferral still stands but its reason stopped being true. Both refuse on every state that is not an outstanding deferral, so neither can be used to tidy a box.

**A `failed` outcome makes no close call.** It routes through step 6's FAIL path — report to the user, ask how to proceed — and the box stays `[ ]` with nothing written anywhere. The enum's third arm is consumed here, by *not* closing.

**Group headers close themselves.** When a close leaves its task group with no open `[ ]` children, the script closes the group header `[x]` in the **same write** — so a header normally needs no call of its own, and closing the last child of a group is one invocation, not two. Closing a header directly is refused while a `[ ]` child remains: an `[x]` there would claim work still owed. `--tilde` is the one way to close such a header, because a `[~]` says on its own line why the group is closed without the work. Never close a header by hand to tidy up after a batch.

#### What comes back

**One JSON object on stdout**, every diagnostic on stderr. For example, closing `1.1` of the dry run below returns:

```json
{"story":"042-legacy-import","task":"1.1","box":"x","qualifier":null,
 "census":{"total":7,"open":6,"closed":1,"deferred":0},
 "status_written":{"from":null,"to":"in-progress"},
 "validate":{"errors":0,"warnings":0,"status":"pass"},
 "reason":""}
```

Read the run's state from that object, and do **not** re-open tasks.md for it:

- **`census`** — `{total, open, closed, deferred}` over the whole file, task list **and** Quality Gates, measured *after* the write. This is the story's progress; a re-read would only be a second, later opinion about the same file
- **`status_written`** — `{from, to}` when this invocation wrote the story's `status:`, and **`null`** when it wrote none. `from` is `null` on a legacy story that had no field to move. `null` covers every non-transition: rule 4 fired, or the field already read the value the table asked for — rule 1's parenthesised no-op — or no artifact carries frontmatter. The field reports what was **written**, never which rule was evaluated — which is exactly what makes it the archive offer's trigger (see Status Transitions, then End of Run)
- **`qualifier`** — the bare token (`deferred` | `waived` | `n-a` | `superseded-by`), `null` on a plain `[x]`. The reason **text** lives beside the box in tasks.md and is deliberately not carried here
- **`validate`** — the story's verdict `{errors, warnings, status}`, taken by the script itself after both writes; **`null` when no verdict could be taken**. `null` means *no verdict*, never *no errors* — report the story as unvalidated and say so (the script says why on stderr). Errors here **never** roll the marking back: a close whose story fails validation still exits `0`, because the close succeeded and the story has errors, and both are true at once. Surface the counts and carry on
- **`reason`** — why a refusal refused; empty on success

**Why the script validates at all.** A Bash write fires no PostToolUse hook, so the per-marking validation `hooks/hooks.json` would otherwise trigger is carried by the script instead.

#### Exit codes, and refusals

| Exit | Meaning | What the orchestrator does |
|---|---|---|
| `0` | the box was closed | read `census`, `status_written` and `validate` from the JSON and continue |
| `1` | **refused** — nothing was written, not even a temp file | surface `reason` verbatim; never retry with different arguments to get past it |
| `2` | the command line is malformed — **no JSON at all** | fix the call and re-run |

A refusal names its own reason in `reason`, and each arm is a statement about the world rather than about the call:

- the box does not exist in this story's task list, or no Quality Gate opens with that prefix
- the box is **already closed**, naming the state it is in
- the `--tilde` qualifier is outside the four-form grammar
- `--tilde` names a qualifier and gives **no reason**
- the `--tilde` reason smuggles a **second** qualifier token — every reader matches a qualifier anywhere on the line, so the file and the report would end up disagreeing about the same box
- the target is **ambiguous**: more than one line answers to it, and which one was meant is not something a writer may guess
- the story lives under `.epico/archive/` — an archived story is read-only
- the group header still has open children (above), or the story, its `tasks.md`, or the rewrite itself could not be reached
- at engineering level `project` or `product`, a Standard or Full sub-task whose `Tests:` field is not `None` and which has no entry in `.draft/red-evidence.yaml` — record its Red first; a box closed without it surfaces only at validation, as a `missing_red`

**On a resumed run, "already closed" is benign confirmation, not a failure.** A run interrupted after a close and before its report is replayed over boxes that already carry their mark: read that refusal as *this one is already done*, log it, and move to the next box. Do not "repair" it by editing the file. The script stays strict on purpose — outside a resume, a second close is a real disagreement about what happened, and a silent one is what the refusal exists to prevent.

**Close one story at a time.** The post-compaction restore (`hook-session-restore.sh`) takes the **most-recently-modified story** under `.epico/stories/` as the active one, so interleaving closes across two stories mid-run points it at whichever story was written last. The script itself only ever touches the story it was invoked for — the hazard is in the ordering, not in the write — so finish one story's closes before starting another's.

### Status Transitions

Every marking can move the story's `status:` field. **Read [run-status.md](run-status.md#status-transitions) before the first close** — the transition table, the census that feeds it and the write mechanism live there.

### The Commit Field

**The tail of a group runs in one order:** close the boxes through `close-subtask.sh`, take the status census it runs (which may write `done`), execute the group's `Commit:` field with its pre-authored message, then make the archive offer if the story is complete. The census precedes the commit deliberately — a group that finished is `done` before its commit exists, so the commit records a state the file already claims rather than one it is about to.

**Dependency satisfaction reads the boxes that exist.** A group carrying a `Commit:` field has no Commit box, so nothing in the plan waits on one.

Always executed by the main agent (not a sub-agent). Git operations require the main worktree context, so in a parallel batch the commit runs **after** the merge and never inside a worktree (see Parallel Execution).

**Stage by name, never `git add -A` or `git add .`.** The commit stages the files the sub-tasks named and nothing else. A blanket add sweeps in whatever the run happened to leave beside them — `.epico/` included, whenever no ignore rule covers it. An ignore rule written by a session hook is absent from every session where that hook did not run, and a rule that only holds when a hook fired is not a rule. Staging by name also keeps the generated artifacts, the runtime data file and the compiled binary out of the commit without depending on a `.gitignore` anyone remembered to write.

**Commit as the identity git already has — never supply one.** Check `git config user.email` once before the first commit. When it is empty, make **no** commit: the boxes stay closed, the changes stay uncommitted, and the closing message gives the user the two `git config user.name` / `user.email` commands and the pending commit messages. Never pass `-c user.name=…`, `-c user.email=…`, `--author` or `GIT_AUTHOR_*` / `GIT_COMMITTER_*`, and never run `git config user.*` with a value: a name inferred from the session puts someone's signature on a commit they never made. `hook-commit-identity-guard.sh` denies all of these.

**Nothing leaves the machine without an explicit answer.** The commit is local and is the last git step a run takes by itself. Push, merge, tag, publish a release or open a pull request only when the user has answered yes to that action in this session — a plan, a `--auto` flag or an earlier yes to a different action is not that answer. Without one, the closing message names the command that would do it, and the run ends there.

**When `.epico/` is untracked and no ignore rule covers it, leave it that way and say so in one line.** Do not add an ignore rule on the story's behalf: whether the artifacts belong in git is the workspace's policy to declare, and `scripts/epico-gitpolicy.sh` is what reports a workspace contradicting itself. Silently committing them decides that policy by accident.

**A missing commit is caught on disk, not left to memory.** `hook-commit-guard.sh` runs when a turn ends: a group whose sub-tasks are all settled and whose `Commit:` message is not a commit subject blocks the stop once, naming the message. It stays silent with no git identity — the rule above already makes no commit then — and on the second stop attempt.

**The message is the pre-authored one, verbatim.** The `Commit:` message was written at plan time and carries the story's `type(NNN):` anchor — the one `validate-story.sh` lints for and `story-git-status.sh` counts back as `anchored_commits`. Rewording it at commit time spends that anchor, and the story's own commits stop being findable. The Executor never runs `git commit`: it reports, in its closing block, the pre-authored message it validated against, and the orchestrator is what executes it.

### Deferred Red for E2E sub-tasks

Most Standard/Full pre-authored tests have their Red confirmed by the Test Advisor at plan time (Phase 3) — their `.draft/red-evidence.yaml` entry records `failed: true` with a `reason` and `command`. **E2E tests are the exception.** An E2E test usually needs the application running, a browser driver, fixtures, or a built artifact — none of which exist at plan time — so the Test Advisor authors the E2E test but **defers** its Red confirmation, recording an entry with `red_deferred: true` and **omitting** `failed`, `reason`, and `command` (no run happened in Phase 3). The orchestrator owns that deferred Red check, and it runs at task-execution time:

For a sub-task whose pre-authored test's `red-evidence.yaml` entry carries `red_deferred: true`:

1. **Before spawning the Executor**, the orchestrator runs the materialized E2E test and confirms it **FAILS (Red)** — the behavior under test is absent or not yet correct. This is the same "valid Red" bar used elsewhere: the run must reach an assertion and fail there (`red_at: assertion`); a failure before any assertion — syntax error, wrong import, misconfigured runner, missing driver — is `setup` and **not** valid Red. Record the confirmed Red on the entry: `failed: true`, `red_at: assertion`, `reason`, `command`.
2. **If the deferred Red does not fail as expected** — it passes, errors out, or cannot be run — the orchestrator does **not** spawn the Executor. **STOP and escalate to the user**, describing the test, the sub-task, and the unexpected result.
3. If Red is confirmed, the orchestrator spawns the Executor for the sub-task as normal.
4. **After the Executor completes**, the orchestrator runs the same E2E test again and confirms it now **PASSES (Green)**. A still-failing test is a failed sub-task — report it and stop, as with any validation/test failure.

**The Executor's protocol is unchanged.** The deferred-Red check is **orchestrator-owned**: the orchestrator runs the test before and after, the Executor never performs it. The Executor still receives the pre-authored E2E test as its read-only **"Pre-Authored Test"** input and therefore still treats the sub-task as a **test-first sub-task** — its conditional step 2/5 branching (step 2 Implementation/Green, step 5 Refactor) applies exactly as documented in the Executor Sub-agent section. No new or E2E-specific Executor protocol is introduced; `red_deferred` changes only *when and by whom* the Red is confirmed, not the Executor's six steps.

**Absent `failed` is valid for a `red_deferred` entry.** Run mode MUST distinguish two states of the `failed` key in `red-evidence.yaml`:

- `failed` key **absent** on a `red_deferred: true` entry — **valid**. No Phase 3 run happened by design; Red is confirmed at run time by the flow above. Run mode does **not** treat a missing `failed` key on a `red_deferred` entry as missing or invalid Red evidence, and does **not** block on it.
- `failed: false` **present** — a broken test that did not establish Red. This blocks Phase 3 and is **distinct** from an absent `failed` key. It is never produced by a `red_deferred` entry.

## Executor Sub-agent

The Executor is a dedicated sub-agent that implements a single sub-task following a strict 6-step protocol. The protocol is the Executor's entire purpose — no step may be skipped or reordered.

### Executor Prompt Template

> "You are implementing a sub-task from a structured story plan. Your tech context is [tech_profile.language] with [tech_profile.frameworks].
>
> ## Your Task
>
> **Sub-task:** [number] - [name]
> **Objective:** [objective field]
> **ToDo:** [todo field]
> **Context:** [context field — Files, Docs, Research — if exists; step 1 reads it]
> **Validation:** [validation field]
> **Tests:** [tests field, if exists]
> **Acceptance:** [acceptance field, if exists]
> **Requirements:** [requirements field]
> **Commit:** [the group's `Commit:` message, verbatim, when this sub-task is the group's last — your closing block reports it]
> **Comment language:** [English only — or English plus <language> on the line below, when the user asked for it]
> **Language rules:** [`references/language-rules.md#<language>` for each detected language — read those sections before implementing; or `no language-rules.md section for <language>`]
> **Story directory:** [absolute path to .epico/stories/NNN-slug in the main tree — your progress notes go there, never into a worktree copy]
>
> ## Story Context
>
> [Relevant requirements from story.md — only the Rn referenced by this sub-task]
>
> ## Design Context
>
> [Relevant component interfaces from design.md — only the components this sub-task implements, including exact struct definitions and function signatures]
>
> ## Project State
>
> Files created/modified by previous tasks: [list with paths]
> Design deviations from previous tasks: [deviation register entries, if any]
> Prior deviations and discoveries on this project (from memory — verify before relying on any): [memory hits from step 6a, if any]
>
> ## Pre-Authored Test
>
> [INCLUDED ONLY when this sub-task has a pre-authored failing test. Path to the materialized test file plus its contents. This is a **read-only input** — you implement against it to make it pass; you do NOT author, replace, or weaken it. If this section is absent, this is a test-after sub-task: author tests yourself in step 5.]
>
> ## Unit Test to Write First
>
> [INCLUDED ONLY for a `Unit` sub-task of a **Standard** story: the Tests field (file and scenarios). You write this test before the code, against a stub, and confirm Red at the assertion — see "Executor-authored Unit test" in your agent definition.]
>
> ## Docs already fetched
>
> [INCLUDED ONLY when the orchestrator already queried a docs or research MCP for this sub-task: the source and the passage. You hold `WebFetch`/`WebSearch`, not the MCPs themselves.]
>
> ---
>
> ## Execution Protocol
>
> Execute the six steps of your Execution Protocol **in order**, exactly as your agent definition states them. Nothing in this prompt restates or overrides the protocol, the report format, the closing block or the prohibitions.
>
> **Only step 2 and step 5 change wording**, and only with what this prompt carries above:
>
> - a **test-first** sub-task (one that carries a "Pre-Authored Test" section) makes step 2 Implementation (**Green** — make that test pass, assertions frozen) and step 5 **Refactor**;
> - a **test-after** sub-task has step 2 Implementation and step 5 **Tests**;
> - a **Standard Unit** sub-task (one that carries "Unit Test to Write First") makes step 2 author → Red → Green, and step 5 **Refactor**.

**Every report is on disk; the hand-back is short.** The Executor writes its full report to `.draft/reports/<sub-task>.md` and returns its deviation entries, at most 10 lines and the closing block; the Tech Reviewer and the Test Advisor do the same under `.draft/reports/`. On the inline route the main agent writes the same report file itself. Read a report file only when the hand-back says something needs it — with `grep` on the section you need, never the whole file. The Auditor reads `.draft/reports/` as claims to verify.

**Recording an Executor-authored Red.** When the Executor reports a Standard Unit sub-task's inline Red, append its entry to `.draft/red-evidence.yaml` before closing the box — `task`, `target_path`, `command`, `failed: true`, `red_at: assertion`, `reason`, `recorded`, and `recorded_by: executor` — taken from the report's **Red (inline)** section. A report with no such section, or one whose Red failed before an assertion, is a failed sub-task, not a box to close. `close-subtask.sh` refuses the close while the entry is missing.

### Executor Rules

- The Executor does NOT commit code. Commits are handled by the orchestrator from each group's `Commit:` field — post-merge, in the main tree, with the pre-authored message verbatim. A parallel Executor sits in a worktree, where a commit would land on a branch nobody has merged yet
- The Executor does NOT mark tasks — not `[x]`, and not `[~]` either: `close-tilde` is something its closing block *reports*, never something it writes. The orchestrator does the marking, after verifying the report — and it does it through `close-subtask.sh`, the one sanctioned writer of the checkbox grammar (see Closing a Box). This is not a matter of trust: a box marked anywhere else is a box written outside the only writer that takes the census, stamps the status and validates the story in the same transaction — and, inside a worktree, written into a copy of tasks.md that the merge would then have to reconcile
- The Executor does NOT skip steps. If Context Gathering finds nothing useful, the step still executes and reports "no actionable findings."
- If the final validation or test run fails, the Executor STOPS and reports `outcome: failed`. Iterating toward Green inside step 2 is its work; starting another fix round after the final run is not.
- The Executor receives only the relevant sections of story.md and design.md, not the full files, to keep context focused.

## Multi-Tech Review

When a sub-task's `tech_profile` carries two or more technologies that meet at a boundary (handler to template, app to SQL, API to client), Tech Reviewer sub-agents review that boundary after execution — inline or Executor alike. **Read [run-tech-review.md](run-tech-review.md) when the profile has such a boundary** — the trigger table, the reviewer prompt template and the orchestrator's handling live there. A single-technology sub-task skips it, unless its Complexity is `High`, which reviews always (see the Complexity table in Execution Threshold).
## Context Passing Between Tasks

Each Executor sub-agent starts with a fresh context. The orchestrator bridges information between tasks to prevent context loss.

### What Gets Passed to Next Executor

After each sub-task completes, the orchestrator extracts from the Executor's report:

1. **Files modified** — paths only (the next executor reads them fresh via Read tool)
2. **Design deviations** — any intentional deviations that downstream tasks must know about. Example: "AppConfig::from_env returns Result<Self, String> instead of Result<Self, AppError> — downstream callers must handle String errors"
3. **Framework discoveries** — gotchas found during context gathering that apply to future tasks. Example: "Tera requires all variables referenced in {% if %} to exist in context, even with empty values"

When a sub-task has a pre-authored failing test, the orchestrator also passes the **pre-authored test as a read-only input** — the materialized test file's path and contents in the Executor prompt's "Pre-Authored Test" section. The Executor implements against that test to make it pass and does not author, replace, or weaken it.

### What Does NOT Get Passed

- Full file contents (executor reads files directly)
- Implementation details beyond deviations (executor follows its own ToDo)
- Validation output (only PASS/FAIL status)

### Deviation Register

The orchestrator maintains a deviation register across task execution — **written only through `epico-deviation`**, never by an `Edit`, a heredoc or an inline script. The script owns the format, gives each entry a stable `id`, and writes atomically under a lock:

```bash
epico-deviation add deviation --story <dir> --task 2.1 --component "…" --design "…" --actual "…" --reason "…" --impact "…" [--test-surface-adjusted] [--follow-up "<what is owed>"]
epico-deviation add discovery --story <dir> --task 5.3 --tech "…" --finding "…"
epico-deviation list --story <dir> [--open]           # JSON; --open = entries with follow_up: true
epico-deviation discharge --story <dir> --id 3 --evidence "<what paid it>"
epico-deviation amend --story <dir> --id 3 --impact "…"   # correct a field
```

A register it cannot read — a multi-line value, a nested mapping someone wrote by hand — is refused with the line number; fix that line, never rewrite the file around it. The file looks like this:


```yaml
# .epico/stories/<name>/.draft/deviations.yaml
deviations:
  - task: "2.1"
    component: "AppConfig::from_env"
    design: "Result<Self, AppError>"
    actual: "Result<Self, String>"
    reason: "AppConfig is used in main before AppError module is available"
    impact: "main.rs uses unwrap_or_else — no downstream AppError conversion needed"
  - task: "3.1"
    component: "AppError::Display"
    design: "user-friendly messages only"
    actual: "includes variant prefix 'Database error:'"
    reason: "single Display impl serves both logging and response"
    impact: "HTTP error responses leak error category name"
  - task: "4.2"
    component: "parse_config signature"
    design: "parse_config(path: &str)"
    actual: "parse_config(path: &Path)"
    reason: "callers already hold a Path; &str forced a redundant conversion"
    impact: "call surface only — no behavior change"
    test_surface_adjusted: true   # executor adjusted the pre-authored test's call-site to match
discoveries:
  - task: "5.3"
    tech: "actix-web"
    finding: "HttpMessage trait must be imported for extensions_mut()"
  - task: "7.1"
    tech: "Tera"
    finding: "Variables in {% if %} must exist in context — default filter only works in {{ }}"
```

Either kind of entry carries the optional boolean field `follow_up: true` when it leaves work the run did not do — a correction, an adjustment or a refactor the code now owes, or a story, design or task list that no longer describes what was built. The orchestrator sets it when it records the entry, from the Executor's report; an entry that only explains a choice already made leaves it absent. It is what the end-of-run question reads to recommend Refine ([End of Run](run-end.md#end-of-run--next-step-index)), so a pending fix is a field, not a judgment made at the end.

**A box whose test was rewritten does not close.** When a sub-task has a `red-evidence.yaml` entry, `close-subtask.sh` runs `epico-test-diff` on its `target_path` before marking `[x]`: setup edits pass, an assertion line changed, removed or added refuses the close, and nothing is written. Report that refusal as the sub-task's failure — never restore the box by hand, and never close it `[~]` to get past it. The release is the user's, through refine ([refine-mode.md](refine-mode.md#releasing-a-test-blocked-by-epico-test-diff)).

A deviation entry carries the optional boolean field `test_surface_adjusted`. It is `true` on a deviation where the Executor edited a pre-authored test outside its assertions: imports or signature call-sites to match an INTENTIONAL design deviation, or the setup repair the frozen-test rule allows — fixtures, helpers, imports, paths — when the test could not run in this tree. Assertions are never touched, and the Executor re-confirms Red at the assertion before implementing. The field is absent on deviations that did not require any test change.

The register is:
- Updated after each Executor completes
- Passed as "Project State" context to subsequent Executors
- Included in the Auditor's context during validate-mode
- Written to `.draft/deviations.yaml` for persistence across sessions

## Parallel Execution

Two or more pending tasks whose dependencies are all satisfied may run at once, each in its own worktree. **Read [run-parallel.md](run-parallel.md) before grouping anything** — detection at both levels, the file-collision test, the worktree protocol and the merge order live there. A run that takes one sub-task at a time never opens it.
## Run Mode Rules

- **Parallel when proven, sequential otherwise** — a group that passed the three detection checks (see [run-parallel.md](run-parallel.md)) runs in parallel without asking; everything not proven independent runs in order, respecting dependencies. `--serial` forces order for the whole run
- **Stop on failure** — if validation or tests fail, stop and report. Do not continue to next task.
- **A failure case with no executed test keeps the box open** — when a sub-task's `Tests` field names failure cases ([tasks.md](tasks.md#rules), rule 13), the box closes only when each case has a test that ran; a case written but never run counts as absent, and the run report says which
- **Reach — nothing leaves the machine unless the requester asked for that exact step**: no upload, push, outside login or message, nothing written or deleted outside the project and its own temporary directory; when the requester cannot reach what was built, tell them how to get it and never move it for them ([lean-route.md](lean-route.md#the-floor--every-program-however-small))
- **Host — every process the run started is stopped before the closing** unless the requester asked to keep it, and **nothing opens on the requester's desktop unasked** ([lean-route.md](lean-route.md#the-floor--every-program-however-small))
- **No step skipping** — every step in the Executor protocol is mandatory. Context Gathering is not optional when a Context field exists. Validation commands must be executed and their output reported. This is the fundamental rule of Run Mode.
- **Run-time questions count against the story's question budget** ([clarify.md](clarify.md#clarify-protocol)). A decision with a default in the constitution's `## Defaults` block or in the [plain register](plain-register.md#decisions-the-requester-is-not-asked) table is taken and mentioned, never asked
- **For a `layperson` requester** ([plain-register.md](plain-register.md)): run and show — never ask them to run a command; a stop per group is promised only when `--step` was passed — under the Fast default the run goes to the end and shows the result once, and a doubt the defaults do not cover stops it like a failure would — and when it is promised, it is one group per turn; visible text per turn stays under ~1,500 characters, the rest goes to files. **A build turn writes nothing to the chat between tool calls**: the step-by-step is collected as it happens and written into `run-report.md` once at the end of the turn — one `Write`, never an `Edit` per step (Fast already writes that report) — and the turn's only visible text is its closing three lines — what to type, what it does, and one choice that was made for them. **The turn that finishes the run still ends with the next-step question**, after those three lines: a question is not text between tool calls, and the form rule never removes it ([End of Run](run-end.md#end-of-run--next-step-index)) Notes written between tool calls are where jargon leaks into the chat, and what pushes a build turn over its character ceiling
- **User gates** — controlled by execution flags (default: gate after every task group)
- **Supervisor messages are read at every group gate**: `epico-inbox --story <dir>`. When it prints anything, follow [supervision.md](supervision.md) before the next group — verify each claim, adjust if it reproduces, reply either way. A box close relays them too, through a hook
- **The context band is read after every task group**, gate or no gate: `epico-telemetry | jq -r '.context.band'` ([Measure the context window first](run-end.md#measure-the-context-window-first)). `high` and `efficient` go on. **`degraded` stops the run at that group boundary**: the closed boxes stay closed, and the closing recommends a new session with the command to type after `/clear` — `/epico:epico stories NNN run all`, which resumes from the first open box. Under `--auto` too: a degraded context is not a gate `--auto` may answer, since the answers it would give get worse. A `null` band is unknown — go on, and say once that the context was not measured
- **Context is fresh** — each Executor reads files directly. The orchestrator passes only metadata (paths, deviations, discoveries) between tasks.
- **Commit granularity** — follow the Commit fields defined in tasks. Never commit in the middle of a task group.
- **Completion** — a story is **complete** when **no `[ ]` remains**: it is **`done`** when every box is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), and **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`. `done-except-external` is computed at read time, never written to a file. Progress reads `closed/total (+D deferred)`. See [tasks.md](tasks.md#completion)
- **Marking** — every box this mode closes is closed by `close-subtask.sh`, one invocation per box; the orchestrator never edits a checkbox, and never re-reads tasks.md for a census the call already returned. See Closing a Box
- **Lifecycle status** — Run mode writes `status: in-progress` when a census finds the field absent or `draft`, or finds an open `[ ]` on a story reading `done` or `validated` (the reopen edge), and `status: done` when a marking leaves no `[ ]` and no deferred `[~]`. **Run mode writes none of it by hand**: the same `close-subtask.sh` invocation that closed the box takes the census, applies the table, stamps every artifact that carries frontmatter — the same value in each, the field added on a legacy story with the state this run observed and never a back-dated one — and reports what it wrote in `status_written`. A failed write is reported and the run continues. See Status Transitions
- **Quality gates check** — after all tasks complete (or after the last requested task), run through quality gates and report status; gate commands run with `epico-check run -- <cmd>` ([check-reuse.md](check-reuse.md)). Settling a gate box is a marking like any other: it is closed with `close-subtask.sh <story> gate:<text prefix>` and carries its own status transition, since it is usually the marking that closes the story's last box
- **Next-step question** — a run that ends without a failure closes with one `AskUserQuestion` offering **one** next step — refine when the plan is owed a change, run the rest when boxes are open, validate otherwise — plus *Stop here*; the context `band` that `epico-telemetry` reports decides whether it runs in this session. Archive is never offered here. See [End of Run](run-end.md#end-of-run--next-step-index)
- **Spike promote offer** — when a run **sets** a `scale: spike` story's `## Verdict` to `promote`, offer to create the follow-up story, pre-filled with the spike's `conclusion:`. It is offered **at that moment, not at end of run**, and so lands ahead of the Archive offer — which is the order that works, since a promote whose follow-up was never created is not archivable yet. **The offer is defined once**, in [list-mode.md](list-mode.md#spike-lifecycle) — its gate, the ask-first rule, what is recorded on acceptance and the repeat after an interrupted run all live there, and Run mode reuses them unchanged. A spike's deliverable is the answer, and `promote` is the answer "this needs a story": the offer is how that answer becomes one, instead of a note nobody acts on
- **No archive offer** — a run that writes `done` has closed its boxes, not checked its result: the archive is offered only at VALIDATE's pass point ([validate-mode.md](validate-mode.md#archive-offer)), and `archive-story.sh` refuses a story that is not `validated` unless the user passes `--force <reason>`
- **Index refresh** — regenerate the managed index block at the end of a completed run: `epico-index`. Defined once, in [validate-mode.md](validate-mode.md#index-refresh); a non-zero exit warns and never gates the run
- **The recorded line** — the end-of-run report opens with the line the execution plan opened with — scale, requester level, engineering level with its multiple, plan size in Task List boxes — and adds the wall clock and the boxes closed beside it ([engineering-level.md](engineering-level.md#where-it-is-recorded)). It lets the run's actual size and wall clock be compared against the engineering level's expected multiple; a report without it cannot be measured

### End of Run — next step, index

A run that ends without a failure finishes with the next-step question and the index refresh. **Read [run-end.md](run-end.md#end-of-run--next-step-index) before the closing message** — the step order, the loss annotation, the context band, which step to offer and the question's shape live there, and so do the [Assumptions under `--auto`](run-end.md#assumptions-under---auto).

## Progress Tracking

`tasks.md` is the progress record, and `close-subtask.sh` validates the story on every close. **When the Task tools are present** (`TaskCreate`/`TaskUpdate`, or `TodoWrite`), mirror the run in them for the user to watch — pending, in progress (with the Executor's status), completed once the sub-task passed validation and tech review **and its box is closed**. When they are absent, do nothing: they are offered only on some models, and nothing depends on them.

## Handling Missing Tasks for Quality Gates

If after running all tasks, a Quality Gate is unmet and no existing task covers it:
1. Report the unmet gate
2. Ask user: "Create a new task to cover this gate, close it as N/A, or skip?"
3. If create: generate a new task following the standard format, append to tasks.md, and execute it
4. If N/A: close the gate with `close-subtask.sh <story> gate:<text prefix> --tilde "n-a: <reason>"`, the reason being the user's own (see Closing a Box). Skip closes nothing — the gate stays `[ ]` and the story stays short of `done`
