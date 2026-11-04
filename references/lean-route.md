# Lean Route — `experiment` work, done directly

Loaded when triage reads the engineering level as `experiment` ([triage.md](triage.md#triage-protocol), step 3a), and by `/epico:epico instant`, which enters here without reading the level ([instant-mode.md](instant-mode.md)). **From here this file replaces the rest of triage, Clarify, the phases and Run mode.**

**Why it exists.** An `experiment` buys the security floor and nothing a plan keeps: nobody maintains it, so nobody reads its story. The same model, given only the floor and the check below, delivers what a Fast `experiment` story delivers — the atomic save, the corrupted file, the README and the commit are what it would otherwise miss, not the plan or the questions — at a fraction of the clock, the tokens and the questions.

## What it does not write

**No story.** Nothing under `.epico/stories/`, no `epico-next-number`, no `tasks.md`, no proposal to confirm, no sub-agent but the final reviewer below, no `epico-close` or `epico-progress`. The work is the deliverable and the closing message is its record. A thing nobody will maintain has no plan for anyone to read later.

**Never inside an existing story.** A run of story NNN follows [run-mode.md](run-mode.md) whatever its level; this route is an entrance for new work only.

## Before the work

- **Who is asking** is still read from the request ([triage.md](triage.md#triage-protocol)), and it still sets the register the chat is written in: for a `layperson`, plain words and a term explained the first time it appears ([plain-register.md](plain-register.md) — read it only when the reading is `layperson`).
- **The model is suggested once, never asked — and never for a `layperson`.** When this session is not on Sonnet and the requester is a `developer`, the first line — before any work — says so: Sonnet does this work at the same quality for about a third of the cost; `/model sonnet` switches this session and also makes Sonnet the default (for this session only: open `/model`, pick Sonnet, press `s`); `claude --model sonnet` starts a new session already on it, for that session alone. Then the work starts. A beginner cannot weigh a model, and offering one invites a question they cannot answer. Under `--auto` or headless the line is left out.
- **One line names the level and how to leave it** — never a gate: *"I'll treat this as something to try out and throw away; if you will keep using it, say so and I'll build it to last."* In the requester's language and register.
- **Ask only when the answer changes what is built** — an operation the request leaves out, a field it does not name. Any other open choice is taken as the sensible default and named in the closing. The interface — menu, prompts, messages, README — speaks the language the request was written in, inferred and stated on its line, never asked; the English rule is about artifacts ([SKILL.md](../skills/epico/SKILL.md#language)).

## The floor — every program, however small

The [security floor](quality-catalog.md#the-security-floor--five-items-no-level-drops), plus the commit:

- **Runtime** — a supported version declared where a tool reads it (`engines` in package.json, the `go` line of go.mod, `requires-python`, `rust-version`, or `.tool-versions`).
- **Secrets** — none in the tree.
- **README** — how to run it and how to check it, two lines at least.
- **Dependencies** — prefer none; any added has no known vulnerability. No dependencies is a verdict, not a failure.
- **Data integrity**, when the program writes a file it reads back — written through a temporary file renamed over the target; a missing file and a corrupted file each start the program without a crash and without overwriting the original. A file that parses but has the wrong shape counts as corrupted; a corrupted file is set aside under a timestamped name, never over an earlier one; a save that fails says so. Tests prove these cases.
- **Commit** — when the folder is a git repository with an identity, commit the work, staging files by name. With no repository or no identity, say so in the closing instead; git is never a question for a `layperson`.

**Reach — nothing leaves the machine unless the requester asked for that exact step.** No upload to a file host or a paste site, no repository created or pushed, no login to an outside account, no message sent, no file written outside the project and its own temporary directory, and no `rm -rf` with a glob outside them. When the requester cannot reach what was built — the program runs where they are not — say so plainly and tell them how to get it; **never move it for them**. A yes/no question is not the ask: a `layperson` cannot weigh what publishing exposes, so the step comes from their own words or not at all.

**Host — every process the run started is stopped before the closing**, unless the requester asked to keep it running; then the closing says how to stop it, in one line. And **nothing opens on the requester's desktop unasked** — no browser, terminal or file manager launched for them: show the result in the chat, and open a window only when they asked for that window. A server left running holds a port and memory nobody knows about, and a window that appears unasked is a surprise on someone else's screen.

## Done means the check passed

**Before the code, list the failure cases first** — every rule the request states about bad input, end of input or the data file, and each floor case — one line each, written as the names of the tests, before any code and never narrated in the chat. They are the cases a run that skips the plan forgets first. Then **one automated test per case**, plus tests for what was built; **a case whose test did not run is not done**, and the closing's `Not verified:` line names it. Then **the project's whole check** — tests, plus lint or type check where the stack has one — **run and fixed until it passes** — each run as `epico-check run -- <cmd>` ([check-reuse.md](check-reuse.md)). Run the program once the way the requester will. **A web page is checked at the URL the server itself printed** — started on a free port, or port 0, never a port another program may hold — with `curl` before it is called working; a page answered by someone else's server is the false pass this rule exists for.

**Then one converge pass**: re-read the request and the floor above against what was built. Each gap it finds is reproduced first — a command whose output shows it — and fixed only then: no reproduction, no change. The pass adds work, never re-plans it, and it stops at the first pass that finds nothing ([run-end.md](run-end.md#converge)).

**For a `layperson`, the converge pass is a fresh reviewer's.** Spawn `epico:final-reviewer` once, **after the commit** — so the review sees the work as it will be kept — with the request verbatim and the project directory: it reads code it did not write and reports each gap with the command that reproduces it, and it never edits. A builder re-reading its own work sees what it meant to write; a beginner cannot review it for them. Run each reported command yourself — **only a finding the main agent reproduces is fixed**, then the check runs again and the fix is committed; an `unverified` line becomes a `Not verified:` note, never a change. One review, one round of fixes: a second review is not spawned.

**Neither the converge pass nor the review is announced** — no line before, between or after their tool calls, in any language: the requester sees the closing, and the closing names what changed. **The reviewer's report never reaches the chat**: it is written in English for the builder, and a sentence lifted from it is an English sentence in front of someone who reads another language. The notes these steps would have produced go nowhere; what was fixed is one clause of the closing, in the requester's words.

## The closing

**A `layperson` closing is three lines** — what to type to use it, what it does, and the one decision taken alone that reduced protection most — then the `Not verified:` sentence; **everything else goes to the README**, under a heading in their language that names what was decided for them. The closing stays under ~600 characters, checked with `epico-jargon --max-chars 600` before it is sent ([plain-register.md](plain-register.md#ceiling-per-turn)); a beginner skims a long closing, and the line that mattered is lost in it.

For a `developer`:

- How to run the program and how to run the check, in a line or two.
- **Every decision taken alone that reduces protection or documentation**, one line each with what keeping it would have cost — the requester finds out by reading, never by being bitten. A choice between equivalent means is not listed.
- **When the request is plainly bigger than an experiment** — several integrated surfaces, or something others will depend on — one line says so, and the work proceeds anyway: *"This looks bigger than a throwaway; say the word and I'll redo it as something to keep."* The line is a note, never a gate.
