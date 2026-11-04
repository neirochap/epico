# Validate Mode

Triggered by `/epico:epico stories validate NNN`.

## Contents

- [Post-Implementation Personas](#post-implementation-personas)
- [Validation — Part 1 of the Auditor's spawn prompt](#validation--part-1-of-the-auditors-spawn-prompt)
- [Audit — Part 2 of the Auditor's spawn prompt](#audit--part-2-of-the-auditors-spawn-prompt)
- [Validate Mode Procedure](#validate-mode-procedure)
  - [Fix loop bound](#fix-loop-bound)
- [Status Transition (`validated`)](#status-transition-validated)
- [Integration Warning](#integration-warning)
- [Archive Offer](#archive-offer)
- [Index Refresh](#index-refresh)

## Post-Implementation Personas

These personas are activated **after implementation**, not during story creation. They are optional — activated when the user invokes `/epico:epico validate` on a story directory, or when a sub-agent execution flow completes all tasks.

| Persona | Role | When | Sub-agent type |
|---|---|---|---|
| **Auditor** | Part 1: runs the validation commands, tests and gates ([validation-protocol.md](validation-protocol.md)). Part 2, on a pass: compares implemented code against story + design artifacts | validate mode | `auditor` |

**One spawn validates and audits.** A second agent would re-read the same story from an empty context before the Auditor read it again.

## Validation — Part 1 of the Auditor's spawn prompt

The first block of the one spawn prompt. The Auditor runs it before any audit check.

> "Validate the implementation of these completed tasks.
>
> Tasks file: [path to tasks.md]
> Story directory: [path to .epico/stories/NNN-slug]
> Completed tasks: [list of tasks marked `[x]`]
> Reports: [path to .draft/reports/, if it exists — claims to verify, not facts]
> Review budget: one validation and at most one fix round for this story; this spawn is [the validation | the fix round's revalidation, scoped to: <the failed entries and audit gaps>]
> Pre-filled report: `.draft/validation-report.yaml` — `epico-validate-run` already ran every command it could; its PASS, FAIL and SKIP entries are settled
> Closed without work: [list of tasks marked `[~]`, each with its qualifier — these have nothing to run]
> Project root: [path]
>
> **Settle only the entries whose result is `JUDGE`** — a Validation written as prose, a gate with no command, a span that names a file instead of running one. Never re-run an entry the script settled: it ran the command, checked the test file and the commit, and its evidence is in the file. For each `JUDGE` entry:
> 1. Check what its text asks — run what it describes, read what it names
> 2. If a Tests field exists, verify the test file exists and tests pass
> 3. If the group carries a `Commit:` field, verify the commit was made (check git log)
>
> Then settle the Quality Gates: for each gate in the Quality Gates section, decide from the task results whether it is satisfied, and record it PASS or FAIL with its evidence. A generated gate — one carrying a `Qn` identifier and a command ([quality-catalog.md](quality-catalog.md)) — is settled by running that command: its exit status is the verdict and its output the evidence.
>
> **The CI mirror gate needs a container runtime.** Before running `act`, check `command -v docker || command -v podman`; when neither Docker nor Podman is on PATH, record the CI mirror gate as SKIP with the evidence `not run — no container runtime` — it is never a FAIL, since the work was not shown wrong, only not shown.
>
> Then, as the LAST step before composing any textual summary, rewrite `.draft/validation-report.yaml` with every `JUDGE` entry turned PASS or FAIL and the `verdict` recomputed — the script's entries unchanged — in the story directory — creating `.draft/` on demand is part of that step, since fast and spike stories have none. The orchestrator concludes from that file, not from your reply:
>
> ```yaml
> story: "NNN-slug"                       # the story directory name
> generated_at: "<YYYY-MM-DD>T<hh:mm:ss>Z" # UTC, ISO 8601
> verdict: pass                           # pass | fail — fail when any result is FAIL
> results:
>   - task: "1.1"
>     result: PASS                        # PASS | FAIL | SKIP
>     qualifier: null                     # on a SKIP from a [~] box: deferred | waived | n-a | superseded-by
>     detail: "bats tests/foo.bats — 12 tests, 0 failures"
>   - task: "2.1"
>     result: SKIP
>     qualifier: deferred
>     detail: "closed without the work — needs the provider's live account"
> gates:
>   - gate: "All task validations pass"
>     result: PASS                        # PASS | FAIL | SKIP (the CI mirror without a container runtime)
>     evidence: "no FAIL in results[]"
> ```
>
> One results[] entry per sub-task you were given, `[x]` and `[~]` alike, and one gates[] entry per Quality Gate. A SKIP never fails the run. A `[x]` sub-task with no runnable Validation command is FAIL, never SKIP; a command that hangs or waits for input is FAIL with its reason.
>
> Only then reply, short: line 1 `verdict: <pass | fail | fail-record>`, then one line per gap, unmet gate, `missing_red` and `record_issues` entry, then one line counting what stays in the file (findings, scope creep, claims not confirmed). Never restate the file.
>
> Do NOT modify any other file: that report is your only write, and any other write is a protocol violation — report what is wrong, never fix it."

## Audit — Part 2 of the Auditor's spawn prompt

The second block of the same prompt, run only when Part 1's verdict is `pass` — on a finished story, or on the `[x]` boxes of a partial one. Performs a holistic review comparing what was planned vs what was built.

> "Review the implementation against the story and design artifacts.
>
> Story directory: [path to .epico/stories/NNN-slug]
>
> Files to read:
> - [path to story.md]
> - [path to design.md] (if exists)
> - [path to tasks.md]
> - [path to .draft/deviations.yaml] (if exists)
>
> Prior structural findings on this project (from memory — verify each against the code, and cite only what a file shows; a finding resting on this list alone is a protocol violation): [memory hits, or "none"]
>
> Check:
> 1. Every requirement in story.md is implemented (trace to actual code, not just task checkboxes). A criterion carrying the `(satisfied-by: <artifact>)` suffix is traced to THAT ARTIFACT instead — confirm it exists and answers the criterion, and do not report it as a coverage gap. A suffix naming an artifact that does not exist IS a finding.
> 2. Every component in design.md exists in the codebase with the specified interfaces
> 3. Error handling strategy in design.md is followed in the actual handlers/controllers
> 4. Security considerations in design.md are addressed in the implementation
> 5. Testing strategy levels in design.md all have corresponding test files
> 6. Quality gates in tasks.md are all satisfied
> 7. Scope creep, against a baseline — only what this story provably added (the files its `type(NNN):` commits touched, or with none yet, the files its sub-tasks name plus the uncommitted changes) can be scope creep; code whose origin you cannot tie to this story is an `info` finding at most. When the anchored commit is the repository's root commit, it carries the scaffold too, so the baseline is only the files the sub-tasks name
> 8. If deviations.yaml exists: for each deviation, verify the stated impact is accurate and no downstream breakage occurred. For each deviation marked with limited impact, check actual callers of the deviated component to confirm.
> 9. If deviations.yaml has discoveries: verify each discovery was addressed in subsequent tasks (e.g., if a template engine gotcha was found, check that later tasks using templates account for it)
> 10. Red precedence — at engineering level `project` or `product` ([engineering-level.md](engineering-level.md)), read from tasks.md's frontmatter `engineering:` — `project` when absent; at `experiment` or `tool`, as for Fast and spike, the Red lives in the run report and this check is skipped with `missing_red` left empty: every sub-task whose `Tests:` field is **not `None`** has both a pre-authored test and an entry in `.draft/red-evidence.yaml` with `failed: true` (or `red_deferred: true` for `E2E`); a missing entry is reported as a finding. Since Red evidence is recorded in Phase 3 and implementation happens in Run, the entry's existence establishes precedence by construction. Quantify over the `Tests:` field, never over the set of authored tests — a sub-task added by a refinement after Phase 3 ran has no authored test, so "every sub-task with a pre-authored test" excludes the very sub-task that is broken. Report a non-`None` `Tests:` field with no authored test as its own finding.
> 11. `type: bugfix` only — the guard must bite: run the current regression tests (those of the sub-tasks citing an Expected Behavior item) on the parent of the story's oldest anchored commit, in a scratch worktree under `${TMPDIR:-/tmp}/epic-red/`; they must fail at an assertion there. A pass is an `issue`; a test that cannot run on the old code is a `warning`; no git, no anchored commit or no regression test is recorded as not verified, never as a pass
>
> Then, as the LAST step before composing any textual summary, write the whole audit to `.draft/audit-report.yaml` in the story directory — creating `.draft/` on demand is part of that step, since fast and spike stories have none. The orchestrator concludes from that file, not from your reply; the head is the validation report's, key for key, so one reader parses both:
>
> ```yaml
> story: "NNN-slug"                       # the story directory name
> generated_at: "<YYYY-MM-DD>T<hh:mm:ss>Z" # UTC, ISO 8601
> verdict: pass                           # pass | fail | fail-record — see below
> gaps:
>   - requirement: "R2.3"                 # requirement number, component name or file path
>     detail: "no recovery path when the report is unparseable"
> unmet_gates:
>   - gate: "All tests written and passing"
>     evidence: "tests/foo.bats — 2 failures"
> deviations_reviewed:
>   - deviation: "2.1 — parser inlined instead of extracted"
>     accurate: false                     # is the deviation's stated impact accurate?
>     detail: "claims no callers; src/cli.ts calls it"
> record_issues:                          # the register is wrong or incomplete; the code is not
>   - record: ".draft/deviations.yaml"
>     entry: "2.1"                        # the entry, or `missing` for a deviation nobody recorded
>     fix: "impact: two callers (src/cli.ts:40, src/api.ts:12), not none"
> scope_creep:
>   - item: "retry/backoff added to the HTTP client"
>     detail: "not in story.md, not confirmed during clarify"
> missing_red:
>   - task: "2.2"
>     kind: no-entry                      # a pre-authored test with no entry in .draft/red-evidence.yaml
>   - task: "3.1"
>     kind: no-test                       # a non-`None` Tests: field with no authored test at all
> claims:                                 # Executor-report claims your checks relied on
>   - task: "2.1"
>     claim: "validation exit 0"
>     status: confirmed                   # confirmed | partial | unsupported
>     evidence: "go test ./internal/parser → exit 0"
> not_verified:                           # the loss annotation — mandatory, never omitted
>   - what: "E2E checkout flow"
>     why: "no E2E tool in this story (design.md: E2E tool: none)"
> untested:                               # changed behaviour no test covers — `[]` when every one has a test
>   - behaviour: "the retry after a 503"
>     where: "src/http/client.ts:42"
> verified_at:                            # the fidelity rung the verification ran on, and its gap
>   rung: "local bats suite, normal user"
>   does_not_cover: "the runner's clean checkout — act was not run"
> checks_run:                             # what was run for each check that found nothing
>   - check: "Security"
>     ran: "read src/auth/*.go; gosec ./... → 0 issues"
> findings:
>   - severity: issue                     # info | warning | issue
>     check: "Dead code"                  # the checklist item it came from
>     location: "src/db/pool.ts:88"
>     detail: "import left behind by the refactor"
> ```
>
> Every array is present even when empty (`gaps: []`) — only the empty one says checked and clean. `verdict` is `fail` when any gap, unmet gate or `missing_red` entry exists; `fail-record` when none of those exists but a deviation is inaccurate or unrecorded — each also in `record_issues[]` with its exact `fix`; `pass` otherwise; scope creep and checklist findings are advisory, never held against the run. `missing_red`'s `kind` keeps the two absences apart: `no-entry` for a pre-authored test with no Red evidence, `no-test` for a non-`None` `Tests:` field with no test at all. `untested` lists each changed behaviour no test covers, written `untested: []` when there is none; `verified_at` names the rung the verification ran on and what it does not cover.
>
> Only then summarize in prose:
> - List of gaps found (cite requirement numbers, component names, file paths)
> - List of quality gates not met
> - List of unverified or inaccurate deviations (if any)
> - List of scope creep items (if any)
> - List of sub-tasks with a pre-authored test missing a Red-evidence entry in `.draft/red-evidence.yaml` (if any)
> - List of sub-tasks whose `Tests:` field is not `None` but which have no pre-authored test at all (if any) — the refine-added case, reported separately
> - List of code review findings from the checklist (severity: info / warning / issue)
> - 'All checks passed' if clean
>
> Do NOT modify any other file: that report is your only write, and any other write is a protocol violation — report what is wrong, never fix it."

## Validate Mode Procedure

1. Resolve story directory from NNN
2. Read tasks.md and take the checkbox census. A story is **complete** when **no `[ ]` remains**: it is **`done`** when every box is `[x]` or terminal `[~]` (`waived:`, `n-a:`, `superseded-by:`), and **`done-except-external`** when the only non-`[x]` boxes are `[~] (deferred: …)`. `done-except-external` is computed at read time, never written to a file. Only `[x]` sub-tasks have an implementation to validate — see [tasks.md](tasks.md#completion)
3. Delete the stale `.draft/validation-report.yaml` and `.draft/audit-report.yaml`, run `epico-validated <story-dir>` — it records the commit about to be checked, and whether the tree outside `.epico/` is dirty, in `.draft/validated.yaml`, which archive carries into the manifest (exit 2 outside git: carry on without it) — then run **`epico-validate-run --story <dir>`**: it runs every Validation and gate command (through `epico-check run -- <cmd>`, [check-reuse.md](check-reuse.md)) in seconds and writes the report a sub-agent used to spend minutes producing. **On its `verdict: fail`, spawn nothing**: the validation failed, the audit does not run on a failed validation, and step 5 presents the FAIL entries from the file. On `pass` or `pending`, spawn **one** Auditor sub-agent — `model` set by the `reviewModel` option (SKILL.md, *Plugin options*): `inherit` omits it, `sonnet` or `haiku` passes that value — (`run_in_background: false`) and wait for its completion. It runs the validation first — each task's validation command, tests and gates, per [validation-protocol.md](validation-protocol.md) — and writes `.draft/validation-report.yaml`; on a validation pass it goes on to compare the code against story + design, review the deviation register, and write `.draft/audit-report.yaml`. The spawn prompt is the two blocks below, validation first. When memory is available, it carries prior structural findings recalled with one `memory_query` — `audit OR scope-creep OR false-positive OR recurring`, `limit: 10` — as things to verify ([mcp-integration.md](mcp-integration.md#memory-mcp))
4. Read both verdicts with `epico-report --story <dir>` — never the whole YAML ([output-rules.md](output-rules.md#reading-files-back)). Take the validation verdict from the file `.draft/validation-report.yaml`. On `verdict: fail` the audit file is absent by design — the run is a validation failure. On `verdict: pass`, take the audit verdict from the file `.draft/audit-report.yaml` the same way
4a. **The claims check**, when `epic-supervise` is on PATH and `EPICO_SUPERVISION` is not `off`: run `epic-supervise claims --root <project> --story <NNN> --workspace <ws> --project <proj>` (the ai-memory scope triage resolved) and wait for it. It compares what the run claimed — progress notes, reports, closed boxes — with the exit codes and commits recorded elsewhere, writes `.draft/reports/claims.md`, and adds one finding per divergence to the project's findings store. It never blocks the verdict: its divergences join the results below as claims to verify. Without the command, say so in one line and go on.
5. Present the combined results to the user, composed from the two files: the validation's `results[]` and `gates[]`, the audit's `gaps[]`, `unmet_gates[]`, `deviations_reviewed[]`, `scope_creep[]`, `missing_red[]` and `findings[]` — and always its `not_verified[]`, `untested[]` and `verified_at`, as the last lines, even on a pass
5a. **On `verdict: fail-record`, fix the record yourself.** Apply each `record_issues[]` fix with `epico-deviation` — `amend --id N --<field> …` for a wrong entry, `add deviation …` for a missing one — list every fix in `.draft/run-report.md` under `## Record fixes` and in the presented results, and treat the audit as `pass` from here on. No fix round, no task group, no second Auditor: the code passed, and only the register was wrong
6. If gaps found, offer to create new tasks to address them — **bounded to one fix round**, see [Fix loop bound](#fix-loop-bound)
7. Apply the status transition for this verdict — see Status Transition (`validated`)
7a. **Memory write (when memory is available)** — for each `findings[]` entry that is structural by the Auditor's own criterion (likely to recur in this codebase: a recurring scope-creep pattern, a false-positive deviation, a project-specific gate failure) and for each `deviations_reviewed[]` entry with `accurate: false`, write or rewrite one page at `epico/finding/NNN-<subject-slug>.md`: H1 = the subject, body = the finding, the story it came from and the file/line evidence. Same subject, same path — a finding seen again rewrites its page, and that rewrite is the supersession. A story-specific bug gets no page; it belongs to the tasks step 6 offers ([mcp-integration.md](mcp-integration.md#memory-mcp))
8. On a passing verdict, surface **at most one** integration warning when it applies — run `story-git-status.sh` once, then either report its `anchored_commits == 0` sentence or pipe the same JSON into `epico-integration --validate <NNN>`, which writes the sentence or nothing — then offer the archive and refresh the index. See Ordering at the pass point, then Integration Warning (and its precedence table), Archive Offer and Index Refresh

### Fix loop bound

A **fix round** is one pass of the loop validate fails → fix tasks are created and run → validate again. Unbounded, it is the most expensive thing Epico does: every round re-runs the whole suite and re-reads the whole story in the Auditor, and a finding the fix did not settle — or a new one the fix introduced — sends it round again.

- **The round is counted from tasks.md, never remembered.** The group step 6 creates is titled `Validation fixes — round N`; the next round is one more than the highest `N` already in the file.
- **Every offer states what a round costs**: the fix run plus one Auditor spawn, which validates and audits. When `epico-telemetry` measured this validation, give its `subagent` tokens and its wall clock as the price of the revalidation.
- **Round 1** — offered as step 6 always offered it.
- **After a fix round runs, the revalidation is asked, never chained.** Neither Run mode nor this mode starts VALIDATE on its own after a `Validation fixes` group closes; the next-step question at the end of that run offers it, stating the round and its cost ([run-end.md](run-end.md#end-of-run--next-step-index)).
- **The revalidation re-checks the failures, never the whole story.** Run `epico-validate-run --story <dir> --only <id,id,gate:<prefix>>` with the entries that failed: every other entry keeps its earlier result. Spawn the Auditor again only when a failed entry was `JUDGE` or the audit reported gaps — and then scoped, its prompt naming those entries and gaps as the whole of its work. A failure the script alone settled needs no sub-agent.
- **Round 1 is the only one offered.** When the revalidation still fails, step 6 creates no round 2: present what remains and recommend refining the story, since a finding that survives a fix is usually a plan problem, not an implementation one. Another round runs only when the user asks for it in so many words.
- **Headless** takes the recommended option at each point — so it runs round 1 at most, never revalidates on its own, and logs the command instead.

### The verdict is the file; the reply is a courtesy

Each part writes its report as the **last** step of that part, before composing any prose ([validation-protocol.md](validation-protocol.md), [auditor.md](../agents/auditor.md)), and steps 3-5 conclude from those two files. The final message is a convenience for the human reading along and **the source of no pass/fail decision** — an agent that ends on an intermediate line swallows its own reply, and the verdict is on disk regardless. Without the file, recovering a swallowed verdict costs a `SendMessage` round, or a respawn that re-runs the entire suite.

**Read `verdict`; never re-derive it.** Each part computes its own by its own rule — a SKIP never fails the validation, and scope creep and checklist findings never fail the audit — so a second derivation here is a second rule, and two rules disagree on the first story that tells them apart. The arrays are what step 5 presents and step 6 turns into tasks, never what the pass/fail is computed from.

### Before the spawn, delete both stale report files

Step 3 removes `.draft/validation-report.yaml` and `.draft/audit-report.yaml` immediately before the spawn. Once the agent fails to write, a leftover from a prior run is indistinguishable from a fresh verdict — and *does the file exist* is exactly the test step 4 performs, so without the delete the flow reads last week's `pass` as this run's.

**Both, because one spawn writes both.** A validation `fail` ends the spawn with no audit report, and an audit file left over from an earlier pass would then read as this run's audit.

**Deleting what is not there is a no-op, never an error, and never a reason to skip the spawn.** A fast or spike story has no `.draft/` at all — the Auditor creates it on demand — so a missing file and a missing directory are the ordinary first-run state.

### Absent or unparseable: one re-request, then the run is failed

Apply the first row that matches, once the agent returns:

| # | The report file | Then |
|---|---|---|
| 1 | Present and parses | read `verdict` and carry on — the ordinary case |
| 2 | Absent, empty, truncated, or not parseable as YAML | **one** `SendMessage` to the **same agent** and **never a second**, asking it to write its report file now, then wait for that agent's completion notification before reading the file again |
| 3 | Still absent or still unparseable after that one request | **the run is failed** — report it in those terms and stop |

**One request and never a second, to the agent that already did the work**, because it still holds the context that produced the verdict: re-emitting the file costs a message rather than a validation suite.

**Never respawn silently.** A respawn re-runs every command and every test — precisely the cost the file exists to save — and a second agent that also ends on an intermediate line leaves the flow looping over one failure. Running validate again is the user's call, made with the failure in view.

**Never infer a verdict from prose.** Whatever the agent did say — including a summary that reads like a clean pass — is not a verdict, and the verdict-is-the-file rule has no exception for a missing file: a verdict assembled from chat is the unverifiable claim the file exists to replace.

A failed run **writes no status and makes no offer** — rule 3 below, reached as any failure reaches it.

## Status Transition (`validated`)

Validate mode owns exactly one of the six `status:` values — `validated` — and writes it at exactly one point: a passing verdict. It never writes any of the other five; those belong to CREATE, RUN, the supersede operation and the archive operation. See [lifecycle-status.md](lifecycle-status.md#lifecycle-status-status) for the full field spec.

**The write mechanism is defined once**, in [run-status.md](run-status.md#status-transitions) — `Edit` on the frontmatter line and never `Write`, the same value in every artifact that carries frontmatter, the `Edit` adding the field on a legacy story that never had one. Validate mode reuses it unchanged; restating it here is exactly how the two copies would drift apart. A failed write is reported and the flow continues: `status:` is advisory metadata and must never change, delay or block the verdict it is recording.

**The verdict read here is the files'.** Rules 1-3 turn on the `verdict` field of `.draft/validation-report.yaml` and `.draft/audit-report.yaml` — never on what an agent said in chat, and never on a re-derivation from their arrays (see The verdict is the file, above). Apply the first rule that matches:

| # | The verdict | Then |
|---|---|---|
| 1 | Both files read `verdict: pass`, and no `[ ]` remains | write `validated` (nothing to do if the field already reads `validated`) |
| 2 | Both files read `verdict: pass`, and at least one `[ ]` remains | write nothing — report the pass and state why the status was not advanced |
| 3 | Either file reads `verdict: fail`, or no verdict was readable at all | write nothing — leave `status:` exactly as it was |

`verdict: fail-record` in the audit file reads as `pass` in this table once step 5a has applied its fixes — the code passed and the register now matches it.

**Rule 2 — a partial validation must not manufacture the lie.** `/epico:epico stories validate NNN` can be invoked at any time, including on a story that still has open `[ ]` boxes: the validation simply has fewer `[x]` sub-tasks to run, and it can still pass. Writing `validated` there would immediately trip `validate-story.sh`'s ahead-of-checkboxes warning — `done` or `validated` while a `[ ]` remains — so the engine would have written the exact claim that check exists to expose. Report the pass instead, and say why the status stayed where it is: **`validated` means "the finished story was verified", not "the part that exists so far looks fine".** When the remaining boxes close, Run mode writes its own transition, and the next passing verdict earns `validated`.

**Rule 3 — a failing verdict writes nothing at all.** Not `in-progress`, and not a rollback of a `validated` left by an earlier pass. A failure is a report, not a lifecycle transition; the story keeps whatever state its last real transition recorded. A run failed for want of a readable report lands here too: an unknown verdict is not a passing one.

**`in-progress → validated`, skipping `done`.** A story whose only non-`[x]` boxes are `[~] (deferred: …)` never receives `done`: Run mode writes `done` only when no `[ ]` **and** no deferred `[~]` remains, so such a story stays `in-progress` (see [run-status.md](run-status.md#status-transitions)). Nothing blocks it from being validated. Rule 1 asks for no `[ ]`, and a deferred box is closed, not open — the same reading `validate-story.sh` applies, whose ahead-of-checkboxes check counts `[ ]` only, so `validated` on a `done-except-external` story raises no warning. Such a story therefore runs `in-progress → validated`, skipping `done` entirely.

**The edge follows from two rules**: `done` is withheld while a deferred box remains, and `validated` is granted on a passing verdict. It is written down here rather than left implicit because an undocumented edge in a state machine is how the next maintainer gets it wrong.

**Ordering at the pass point.** Four things happen on a passing verdict, in this fixed order.

| # | Step | Owner | Why here |
|---|---|---|---|
| 1 | Integration warning — validation passed but the story's work is not integrated into the main branch, or carries no anchor for the detection to find | Integration Warning, below | The caveat reaches the user before anything acts on the verdict |
| 2 | The status write above (`validated`) | this section | — |
| 3 | Archive offer, gated on a status of `validated` | Archive Offer, below | Its gate is true only once step 2 has written the value, and `validated` is the one status `archive-story.sh` accepts without `--force` |
| 4 | Index refresh — regenerate the managed block in `.epico/EPICO.md` | Index Refresh, below | It renders what steps 2 and 3 changed: the new status, and the story's new location when the archive was accepted |

This section fixes the order and the reason for it — each step's behavior is defined where its Owner column points.

**The chain is `verdict` → `status:` → offer, and every link is a file.** Rules 1-3 read the two reports' `verdict`, step 2 writes the status they decide, step 3's gate reads that status back, and step 4 renders what steps 2 and 3 changed. No link in it consults an agent's chat message.

## Integration Warning

Step 1 of the pass point. A passing verdict says the work is finished; whether it ever reached the main branch is a fact the checkboxes cannot see — every story can be checkbox-complete with nothing merged. The detection is the same live evaluation LIST annotates from, defined in [list-mode.md](list-mode.md#integration-annotation): computed live, stored nowhere, blocking nothing.

**The warning is rendered by the same script LIST annotates from** — [`scripts/render-integration.sh`](../scripts/render-integration.sh), asked for a different rendering of the same JSON — so the sentence the user reads is the sentence the test suite pins. On a passing verdict, pipe the detector into its `--validate` mode and append whatever comes back to the presented results:

```
epico-git-status <story-dir> \
  | epico-integration --validate <NNN>
```

`<NNN>` is the story number **as the reader knows it** and is interpolated verbatim — pass `006`, not `6`. What the script writes, per the `integrated` field of the detector's JSON (`{story, main_branch, integrated, evidence, anchored_commits, checked_at}`), **documents its three arms rather than prescribing a rendering to perform by hand**:

| `integrated` | The script writes |
|---|---|
| `false` | the warning below, appended to the presented results |
| `true` | nothing — the work is on the main branch |
| `null` | nothing at all — no main branch is resolvable, so the fact is unknowable |

Exit 2 from the detector — not a git repository, or story not found — also emits nothing at all: nothing reaches the pipe and `--validate` degrades silently, the same rule LIST applies. "Not computable" must never dress up as a finding, and a failed detection must never delay, dirty or block the verdict it decorates.

The sentence, spelled once in the script and reproduced here verbatim, with `<main>` filled from the JSON's `main_branch` and `NNN` the number passed on the command line:

```
story is done but no evidence of integration to <main> (no merged feat/NNN-* branch, no (NNN) commit)
```

`<main>` is read out of the report and never assumed: the detector resolves the default branch through four ordered candidates and it is regularly not named `main`, so a hard-coded name would print a branch the reader does not have. The sentence names the two evidence kinds the detection looked for and found missing — a merged `feat/NNN-*` branch (`branch-merged`) and a commit subject reachable from main carrying the `(NNN)` token (`message-ref`). Either alone would have flipped `integrated` to `true`.

**A warning, never a verdict.** Appending it changes nothing else: not the pass, not step 2's status write, not step 3's offer, not the validation's exit semantics. The script holds its half by construction: **every rendering path exits 0**, warning or no warning, so there is no exit status to read and nothing here to branch on — a caller that checked `$?` would turn the warning into a verdict. The one non-zero exit that is not the cost decision (`--should-annotate`, see [list-mode.md](list-mode.md#integration-annotation)) is exit 2, an unknown or missing mode: a caller error, unreachable from a well-formed call.

**When to ask is this mode's half, and the script cannot check it.** The warning's first three words are a precondition — "story is done" is true only on a passing verdict with no `[ ]` left — and the renderer renders whatever JSON it is handed. Rule 2's partial pass must therefore not call it at all: there the sentence would manufacture the very claim rule 2 exists to refuse.

**It never gates the archive.** `archive-story.sh`'s preflight does not consult integration state — an un-integrated story archives exactly like an integrated one. Whether a warned story needs a merge, a cherry-pick or nothing at all is the user's decision; the warning informs that decision and blocks nothing.

### The anchor warning, and which of the two fires

The detector answers **two nested questions**, and step 1 surfaces **at most one** of them. `integrated` asks *did this story's work reach the main branch*. `anchored_commits` — the number of commit subjects reachable from **HEAD** carrying this story's number as a delimited token, by the same `(NNN)` / `NNN-slug` rules the `message-ref` evidence kind applies — asks the question underneath it: *is the work findable at all*. Zero means this story's commits carry nothing that any detector can attribute back to it, on the main branch or anywhere else.

**Counted from HEAD, not from the main branch**, and that is what keeps the two questions apart: a just-validated story normally still sits on its own unmerged branch, so a main-relative count would read zero for every correctly anchored story awaiting its merge — the state the integration warning above already covers.

Same precondition as that warning — a passing verdict with no `[ ]` left, so `status:` reads `done` or `validated` — and the same severity. **A warning, never a verdict.** It is non-blocking and changes nothing else: not the pass, not step 2's status write, not step 3's offer, not the archive. The sentence, with `NNN` the story number as the reader knows it:

```
this story's commits carry no (NNN) anchor — integration detection cannot see them
```

**Run the detector once and decide from its JSON.** The count and `integrated` come out of the same object, so the pipe shown above becomes a second use of that object rather than a second detection — two runs could disagree, and the detector is the expensive half:

```
status_json=$(epico-git-status <story-dir>) || status_json=""
# then, only when the table below says so:
printf '%s\n' "$status_json" | epico-integration --validate <NNN>
```

**Precedence — apply the first rule that matches.** Left to themselves the two warnings double-fire on one story: a story with no anchored commits has no `message-ref` evidence either, so `integrated` is usually `false` for the very same underlying fact, and the user reads two sentences about one problem.

| # | The detector's JSON | Step 1 surfaces |
|---|---|---|
| 1 | `integrated: null` — or nothing on the pipe at all, the detector's exit 2 | nothing whatsoever, whatever the count says |
| 2 | `anchored_commits == 0` | the anchor sentence above, and the `--validate` render is **not** run |
| 3 | `integrated` reads `false` | the integration sentence, from the render above |
| 4 | anything else — `integrated` reads `true` | nothing; the work reached the main branch |

`anchored_commits == 0` **wins** over rule 3 because it is the more specific finding: there is nothing for the detection to see at all, and "merge your branch" is the wrong instruction for a story whose commits carry no anchor to find. The integration warning therefore fires **only when** the story has anchored commits and none of them reached the main branch — the case it was written for.

`integrated: null` silences both, and it is first for that reason. No main branch resolved, so nothing was measured, and *"not computable" must never dress up as a finding* — the rule stated verbatim one field over, applied here to the pair rather than to one of them. `anchored_commits` can be `null` on the same principle, when the count itself was not computable (a repository with no commits at all): it is not `0`, so rule 2 does not match and the count simply adds nothing to a decision rules 3 and 4 already made without it. That combination is close to unreachable in practice — a repository with no commits resolves no main branch either, so rule 1 catches it first — and it is written down because a silence that depends on being unreachable is a silence nobody can check.

## Archive Offer

Step 3 of the pass point, and **the single definition of the offer**. Run mode never makes it — a run ends at `done`, and its next step is this mode ([run-end.md](run-end.md#end-of-run--next-step-index)); [supersede](supersede-mode.md#the-archive-offer) reuses this section for a story absorbed by another. A second copy of a prompt that spends guards is how one of the copies ends up spending them differently.

**Why here.** Archiving is the step most easily skipped, and right after a passing validate is when it is most likely to be done. Offering it anywhere else asks the user to remember; offering it here asks them to confirm.

### Gate

Offer when **both** hold:

1. Both report files read `verdict: pass` **and no `[ ]` remains** — rule 1 of the status table above.
2. `status:` reads **`validated`** after step 2.

**Archive follows validation, and only validation.** When step 2's write failed, the field still reads `done`: report the failure and make no offer — `archive-story.sh` would refuse a story that is not `validated` anyway, and an offer the script refuses is a question wasted. Any other way out — unfinished work, a story absorbed by another — is the user's `--force <reason>`, never this offer's.

**A partial pass never offers.** Rule 2 — a pass with at least one `[ ]` still open — writes no status and makes no offer, whatever the field already says. `archive-story.sh` would not stop it either: its completion check is an **OR** (frontmatter `status` of `done`/`validated`/`superseded` **or** no `[ ]` remaining), so a story left reading `validated` by an earlier pass satisfies preflight with an open box still in the file. The gate is therefore ours to hold. The offer means *this story is finished*, and proposing the archive over open work would stamp unfinished work as complete.

### The prompt

One `AskUserQuestion` — *Archive* first with the recommended marker in the user's language, *Keep it* second. It is the only next step this point offers, since validate has just run and refine has nothing to act on. In logs and below, it is written in its short form:

```
Archive story NNN? [y/n]
```

When the census shows deferred boxes — the computed condition `done-except-external`, defined once in [tasks.md](tasks.md#completion) — list them under the question, so the user accepts with the outstanding work in view:

```
Archive story 003? [y/n]
  Still owed by an external actor (2 deferred):
    - 2.1 — Register the production callback URL (deferred: needs the provider's live account)
    - 2.2 — Verify the first live event (deferred: needs a real payment in production)
```

Render each line as `N.N — title (qualifier: reason)` — the exact shape `archive-story.sh` derives into the manifest entry's `deferred_items[]`, so what the offer shows is what the archive will record.

**The items are shown, never passed.** On acceptance the offer hands the script **no** item list and no counts: `archive-story.sh` derives `deferred_items[]`, `tasks_total`, `tasks_closed` and `tasks_deferred` from the checkboxes itself. Declaring them at the call site would make the manifest hand-declared, and a hand-declared manifest can contradict the boxes it summarizes.

### On `[y]`

```
epico-archive <story-dir>
```

The story number (`005`) works in place of the directory — it resolves against the nearest `.epico/`. Pass **no flags**. `--allow-heavy`, `--skip-secrets`, `--keep-logs`, `--keep-copies` and `--force <reason>` are the user's decisions and each is recorded in the manifest entry as an override: an override the engine chose for itself is an override nobody agreed to. The one `--force` an offer passes is supersede's, and only because its question names the flag and the reason before the user accepts ([supersede-mode.md](supersede-mode.md#the-archive-offer)). Never re-run a blocked archive with a guard flag on your own initiative — report the verdict and let the user ask for the override by name.

The script prints **one JSON object on stdout**, diagnostics on stderr. Surface the verdict by its `status`:

| Exit | `status` | Surface |
|---|---|---|
| 0 | `archived` | The move is done. Report `path`, `tasks{}`, `pruned{logs_kb, copies_removed}`, `overrides_used[]` when non-empty, and `secrets` — including a `skipped` scan, because a scan that did not happen is part of the verdict. `index: "regen-failed"` is a warning, not a failure: the story is archived and the next refresh retries |
| 1 | `blocked` | A guard stopped it. Report `reason` plus every `guard.violations[]` entry (`file`, `size`, `reason`) and `secrets` (`findings`, `report`) verbatim. **Nothing was moved** |
| 1 | `refused` | Preflight said no — already archived, incomplete without `--force`, not a story directory. Report `reason` verbatim. **Nothing was moved** |
| 2 | — | Invalid input, and **no JSON is printed at all**. Report the stderr message: this is a bad invocation, not a user decision |

**Never swallow a `blocked` or a `refused`.** Report the verdict in full, including the offending files and the findings count. A refusal the user cannot see is indistinguishable from an archive that happened.

### On `[n]`

One line, no argument, no second ask: the story stays in `.epico/stories/`. The offer returns on the next passing verdict, and `/epico:epico stories archive NNN` runs the same script at any time.

### Headless

**Only when `AskUserQuestion` is not callable** — not listed among the tools, directly or as a deferred tool to load, per [triage.md](triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage): do **not** pause. Emit the offer as a logged note, with its command, and proceed immediately — the archive is never performed without an accepted offer. **While the tool is callable, ask with it**: `--auto` and a missing Task tool do not count as headless here, because the offer comes after the gates `--auto` answers, and an offer written as prose is an offer nobody can accept. The Task tools are never the signal — Claude Code offers them only on some models.

The note names the command, so a logged suggestion is still actionable:

```
Archive suggestion: story 003 is validated and complete (2 deferred, still owed
externally). To archive it, run:
  epico-archive 003
```

## Index Refresh

Step 4 of the pass point, and **the single definition of the completion-time refresh** — Run mode invokes it at the end of a completed run and LIST refreshes it opportunistically, both pointing here.

```
epico-index
```

It regenerates the managed block between the `<!-- epico:index:start -->` / `<!-- epico:index:end -->` markers in `.epico/EPICO.md` and preserves every byte outside them.

**Why it runs last.** It renders state, so it must run after the state changes: after step 2's `status:` write, and after step 3 resolves. An accepted archive moved the directory and `archive-story.sh` already regenerated the block as its own final step — the refresh is then a zero-diff no-op, which is exactly what idempotent buys here. A declined offer leaves only the new status to render.

**A non-zero exit warns and never gates the verdict.** Exit 1 is a failed regeneration (a broken marker pair, an unreadable or unwritable file — the file is left untouched); exit 2 is invalid input. The index is a rendering of the truth, not the truth: a stale rendering is never a reason to hold, delay or reverse a verdict, and the next refresh retries.
