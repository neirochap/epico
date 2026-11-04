# Init Mode

Triggered by `/epico:epico init`. Interactive wizard to set up project configuration files.

## Contents

- [Procedure](#procedure)
- [Rules](#rules)
- [The reuse profile](#the-reuse-profile)
- [Versioning Policy](#versioning-policy)

## Procedure

1. **Scan project** — detect language, framework, dependencies, existing config files
2. **Check existing files** — report whether `.epico/constitution.md` exists, whether the project has a `CLAUDE.md` and an `AGENTS.md`, and whether `epico-claude-md check` finds the managed block current
2a. **Check memory** — one `memory_status` call ([mcp-integration.md](mcp-integration.md#memory-mcp)). WHEN `ai-memory` answers and the nearest `.ai-memory.toml`, if any, has no `ignore_paths` entry covering `.epico/**`, add one line to the final report: `ai-memory detected — add ignore_paths = [".epico/**"] to .ai-memory.toml so its hooks do not capture the artifacts Epico versions`. Informative, never gating; a non-interactive run prints the same line and asks nothing
3. **Interactive questionnaire** — ask questions in a single numbered block:

   **For `.epico/constitution.md` — always written, mandatory for Standard and Full ([constitution.md](constitution.md)):**
   - Runtime? [1] the host's (default for a `developer`) [2] a venv or language-local environment [3] a container (default for a `layperson`: the program never touches the system it runs on)
   - Testing philosophy? [1] TDD [2] Test-after (default) [3] Minimal
   - Hard constraints? (e.g., "no ORMs", "integration tests hit real DB")
   - Commit style? (auto-detect from git log if available)

   **Worktrees (Claude Code's defaults):**
   - `.claude/worktrees/` goes into `.gitignore` — Claude Code creates sub-agent worktrees there, and they are never project files
   - Offer `{"worktree": {"baseRef": "head"}}` in `.claude/settings.json` — [1] add it (default) [2] skip. Without it a worktree branches from the remote's default branch and misses local, unpushed work
   - `.worktreeinclude` only for ignored files an Executor needs (`.env*`); never `.epico/`

   **Protected files:**
   - The archive: offer `permissions.deny: ["Edit(.epico/archive/**)", "Write(.epico/archive/**)"]` in `.claude/settings.json` — [1] add it (default) [2] skip. Claude Code enforces a deny rule; the archive hook is best-effort and stays as a second line. `epico-archive` moves stories through Bash, which the rule does not cover, so archiving keeps working
   - Files or patterns Claude should never modify? When the user names any, offer to add one `Edit(<pattern>)` rule per pattern to `permissions.deny` in `.claude/settings.json` — a rule Claude Code enforces, where a line in `CLAUDE.md` is only advice. Write it only on the user's yes.

   **Defaults — decisions the requester is never asked** (written into `.epico/constitution.md` as a `## Defaults` block; triage, Clarify and Run read it, and the [plain register](plain-register.md#decisions-the-requester-is-not-asked) relies on it):
   - Data files the program creates? [1] gitignored (default) [2] versioned
   - Tests in Fast stories? [1] written silently (default) [2] asked each time
   - Free-text fields? [1] validated as text (default) [2] fixed lists where the domain has one
   - Branch for story commits? [1] the current branch (default) [2] one branch per story

   Unanswered items take the default, and the block is written either way — so the same request gets the same answer on every run.

   **Quality — the checks every story runs** (written into `.epico/constitution.md` as a `## Quality` block; a story's `## Quality Requirements` legend starts from it — [quality-catalog.md](quality-catalog.md)):
   - The always tier, one line per item with the command detected for this stack: formatter, linter, type checker, test runner, lockfile install, dependency scanner, secrets scanner
   - Context items whose signal the scan found (a `Dockerfile`, workflows, a database, an HTTP surface, a UI)? [1] include each detected (default) [2] ask per item
   - An always-tier item whose tool is not installed? [1] recommend the tool and record the item with that note (default) [2] leave the item out, with the reason on its line

   Unanswered items take the default. Activating an item never installs a tool — the [preferred-tooling policy](preferred-tooling.md) applies. Each command is the one the host can run: check it with `command -v` and write the tool that is there; a missing one is written with `(recommended — not installed)` on its line.

   **Security floor, Reversibility, Invariants:** written from the template every time — the floor from [quality-catalog.md](quality-catalog.md#the-security-floor--five-items-no-level-drops) with this host's commands, the reversibility rule as written, and `## Invariants` empty until the project has one.

4. **Generate files** — create all requested files with sensible defaults based on scan
4a. **Write the managed `CLAUDE.md` block** — `epico-claude-md write`, after the constitution exists, since the block is built from it ([The managed CLAUDE.md block](#the-managed-claudemd-block)). Interactively, when a `CLAUDE.md` already exists, say in one line that the block is appended at its end and nothing else in it changes, and ask once; headless, append it
4b. **Write the reuse profile** — when `.epico/reuse-profile.json` is absent ([The reuse profile](#the-reuse-profile)). An existing profile is never touched
5. **Ask the versioning-policy question** — measure first, offer exactly two options, then write the chosen state. Defined once, below: [Versioning Policy](#versioning-policy). A non-interactive run never asks and never starts tracking
6. **Report** — list all files created, and name the policy that was recorded

## Rules

- Never overwrite existing files without confirmation
- Auto-detect as much as possible from the project (language, framework, patterns)
- Defaults should be safe and conservative
- **The `## Defaults` block is declared once, here, and read everywhere.** Triage, Clarify and Run take its answers silently; a question about one of them later is a defect, not diligence
- **The `## Quality` block is the project's default legend.** A story starts its `## Quality Requirements` from it and adds what the Analyst detected and the request asked; an always-tier item a story leaves out says why on its legend
- Each generated file includes comments explaining its purpose
- **Init writes files and nothing else.** It never runs `git add`, `git rm --cached`, `git commit` or `git checkout` — not in either policy branch, not in a headless run. Choosing to version artifacts is a declaration; committing them is the user's next action, and this is the wizard that must never make it for them

## The managed CLAUDE.md block

`epico-claude-md` owns one block at the end of the project's `CLAUDE.md`, between `<!-- epico:start … -->` and `<!-- epico:end -->`, and never a byte outside it. It is the part of the project's rules every session needs before reading anything else: where the constitution is, the docs the scan found, the order to look things up in ([lookup-order.md](lookup-order.md)), the constitution's `## Quality` commands as "before committing", the code rules, the constitution's `## Invariants`, and where the living examples are — under 100 lines, every section left out when it has no source.

- **No `CLAUDE.md`:** the file is created with the block only. The built-in `/init` can still be run later; it writes above the block.
- **An `AGENTS.md`:** one `@AGENTS.md` line goes before the block, once, so both are read.
- **Refreshed, never edited:** `init --repair` rewrites the block from the current constitution; a hand edit inside the markers is lost on the next repair, so project-specific rules go in the constitution or outside the block.

## The reuse profile

`.epico/reuse-profile.json` tells `epico-check` which validation results may be reused ([check-reuse.md](check-reuse.md)). It is JSON, never YAML, and `epico-check` only reads it: init is the one writer. Init and `init --repair` write it only when the file is absent, never over an existing one.

1. Run `epico-check profile --detect`. It prints the proposal (`tools`, `inputs`) and writes nothing.
2. Show the proposal in one line, e.g. `Reuse profile proposed: tools [node --version], inputs [apps/api/.env.test], mode shadow.`
3. Ask once for the **never-reuse** commands — checks that need credentials, docker, a database or a live service. Ask in Brazilian Portuguese like every other question. Each answer is a literal substring of the check command and goes into `never`. An empty answer, or a non-interactive run, leaves `never` empty and asks nothing.
4. Write `.epico/reuse-profile.json` with `mode: shadow`:

   ```json
   {"version": 1, "mode": "shadow", "tools": ["node --version"], "inputs": ["apps/api/.env.test"], "never": []}
   ```

`shadow` runs every check and records what would have been reused; `on` really skips and `off` records nothing. Init never writes `on`: the requester switches by hand after reading `epico-check stats`. `epico-doctor` warns `no reuse profile — run /epico:epico init --repair` while the file is missing.

## Repair (`init --repair`)

Re-runs steps 1, 2 and 4a against what exists and writes only what is missing or stale: the managed `CLAUDE.md` block, a constitution section the doctor reports absent (asked for interactively, never invented), and `.epico/reuse-profile.json` when the project has none (step 4b: `epico-check profile --detect`, the one-line proposal, the one never-reuse question, written in mode `shadow`). It never overwrites a file, never re-asks the versioning-policy question when `.gitpolicy` exists, and ends with `epico-doctor --summary`.

## Versioning Policy

**Why this is a question and not a default.** The absence of a *declared* policy is what destroys lifecycle history: a track→untrack transition wipes stories, a squash leaves duplicates straddling `stories/` and `archive/`, `.epico` files end up committed THROUGH a `.gitignore` that says they never are, and the policy flips back and forth. Option 1 — **version the `.md` artifacts, ignore `.draft/`** — is *recommended* because it keeps the lifecycle auditable; it is still a *question* because every failure above comes from a policy nobody said out loud.

**The recommended policy tracks exactly `story.md`, `design.md`, `tasks.md`, `EPICO.md` and `archive/manifest.yaml` — never `.draft/`.** `.draft/` is scratch space (run logs, authored tests, phase snapshots, `*.wip`) and is in no policy's tracked set. **That includes the story's evidence — `deviations.yaml`, `red-evidence.yaml`, `validation-report.yaml`, `audit-report.yaml` — by decision, not by omission**: the register is a working record, and its durable forms live elsewhere — the archive's prune keeps a summary, and where the `ai-memory` server is detected the orchestrator writes the register and the structural audit findings as pages ([mcp-integration.md](mcp-integration.md#memory-mcp)). A reviewer who wants the evidence reads it from the story before it is archived, or from the page.

**The per-project choice supersedes any global doctrine.** A global rule that says "never commit `.epico`" — in a user-level `CLAUDE.md` or a personal convention — is superseded by whatever this question records for this project. Init never reads, edits or reports on the user's global configuration; it asks, and the answer governs this repository.

### Step 5.1 — Measure before asking

```
epico-gitpolicy
```

Run it from the **workspace root** — it resolves `.epico/` against `$PWD` — and read the JSON it prints on stdout with `jq`. Every measurement path exits 0; exit 2 is a usage error only (an argument this script does not take), so a non-zero exit here is a bug in the call, never a finding about the workspace.

**The wizard acts on the script's fields; it never re-derives git state by hand.** No `grep` over `.gitignore` to decide whether `.epico` is ignored, no `git ls-files` to decide whether anything is tracked. The script already asks git — with `--no-index`, which is the only way the "tracked through an ignoring `.gitignore`" case answers truthfully — and a second reading of the same facts here would be a second thing to keep in step.

**Read order is a contract, and getting it wrong aborts the wizard.** `git`, `policy` and `verdict` are **total**: present on every path, safe to read unconditionally. The four measurement keys — `gitignore_ignores_epico`, `gitignore_source`, `tracked_md`, `tracked_draft` — are **absent when `git` is `false`**, and `jq -r` renders an absent key as the literal text `null`, not as `false`, `""` or `0`. Under `set -u` a `-gt` against that word aborts with `null: unbound variable`. **Read a measurement key only when `git == true`.** This is the script's own stated consumer requirement, in [`scripts/epico-gitpolicy.sh`](../scripts/epico-gitpolicy.sh)'s header.

| `policy` | `git` / measurements | What init presents before the question |
|---|---|---|
| `undeclared` | `git: false` | "Not a git repository — nothing about tracking was measured." The question is still asked: the declaration is valid before `git init` and takes effect the moment the directory becomes a repository |
| `undeclared` | `gitignore_ignores_epico: false` | "Nothing currently ignores `.epico/`." |
| `undeclared` | `gitignore_ignores_epico: true` | "`.epico/` is currently ignored by `<gitignore_source>`." Name the source file verbatim — which file it is decides what init may offer to do about it (step 5.3) |
| `tracked-md` | any | "This project already declares versioned artifacts (`tracked-md`)." |
| `local-only` | any | "This project already declares local-only." |

When `verdict` is not `consistent`, show it **before** asking, verbatim and with its numbers — e.g. `contradiction: 47 tracked files under an ignoring .gitignore` — so the choice is made against the real state rather than against the intention someone remembers having.

### Step 5.2 — The question

**Exactly two options, and option 1 always carries the recommendation.** Ask with `AskUserQuestion` when the function schema list exposes it; otherwise fall back to the numbered-list prose form, per the Runtime dependency precheck in [triage.md](triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage).

```
How should this project version its .epico/ artifacts?

  [1] Versioned artifacts (recommended)
      Git-track story.md, design.md, tasks.md, EPICO.md and archive/manifest.yaml.
      Ignore .draft/ and *.wip through .epico/.gitignore.
      Your plan, your requirements and your task history become reviewable
      history that travels with the repository.
      Records: tracked-md

  [2] Local-only
      Add .epico/ to the root .gitignore. Nothing under .epico/ is ever committed.
      Records: local-only
```

**Which option is the default answer:**

- No policy declared yet (`policy: undeclared`) → **option 1**. That is the recommended default and the state a fresh init is in.
- A policy already declared → **the declared one**, still with option 1 labelled "(recommended)" and the declared one labelled "(current)". Re-running the wizard must never flip a recorded decision by the user pressing enter: `.epico/.gitpolicy` is an existing file, the Rules above already forbid overwriting one without confirmation, and a policy that flips on a re-run is exactly the flip-flop this section exists to prevent.

**There is no third option, and aborting is not one.** If the user abandons the wizard at this question, write **nothing** — no `.epico/.gitpolicy`, no gitignore edit. The lint then reports `undeclared`, which is deliberately low-signal and surfaces only in `stories full`. A policy nobody chose must never be recorded as one somebody did.

### Step 5.3 — Versioned artifacts → `tracked-md`

Three writes, in this order. The gitignore step is second because it is the only one that can be declined, and neither of the other two depends on its outcome.

**a. Write `.epico/.gitignore`, verbatim:**

```gitignore
# Epico scratch space — never versioned under any policy.
.draft/
*.wip
# A dependency tree under .epico/ is never an artifact — an `npm install`
# run inside a story leaves one.
node_modules/
```

The three patterns are the contract; the comment is the Rules' "each generated file includes comments explaining its purpose". If the file already exists with different content, confirm before overwriting — the Rules forbid overwriting an existing file silently — and keep any extra patterns the user added.

**b. The root-gitignore rule — gated on the source file AND on consent.**

`gitignore_ignores_epico: true` does **not** mean the root `.gitignore` has a line to delete. Git consults three exclude sources and the boolean fires for any of them; `gitignore_source` names the one that actually matched. Only the workspace-root `.gitignore` is a file this wizard may offer to edit.

| `gitignore_ignores_epico` | `gitignore_source` | What init does |
|---|---|---|
| `false` | `null` | Nothing. No rule is in the way |
| `true` | `.gitignore` | **Ask consent, quoting the exact line**; remove exactly that line on a yes |
| `true` | `.git/info/exclude` | **Do not offer a removal.** Report that the rule lives in `.git/info/exclude` — a file local to this clone, which init does not edit — and leave the edit to the user |
| `true` | any other path | The rule is in the user's global `core.excludesFile`. **Do not offer a removal**: that file governs every repository on the machine. Report its absolute path so the user knows where to look |
| — | absent (`git: false`) | Nothing was measured — skip this step and say so. After `git init`, re-run `/epico:epico init` to get the offer |

Locate the line before quoting it:

```
grep -nE '^[[:space:]]*/?\.epico/?[[:space:]]*$' .gitignore
```

That covers the four common spellings (`.epico`, `.epico/`, `/.epico`, `/.epico/`). **If it matches nothing while the lint named `.gitignore`, the rule is spelled some other way** (`.ep*`, `**/.epico/`, a negation interplay) — do **not** guess and do **not** delete a line you inferred. Say the rule could not be pinned to one line, show the file, and let the user point at it or remove it themselves.

The consent prompt states the consequence of each answer:

```
Your root .gitignore ignores .epico:

  .gitignore:12: .epico/

Versioned artifacts cannot be committed while that rule stands. Remove this line?
  [y] remove the line — .epico/ becomes trackable
  [n] keep it — the policy is still recorded as tracked-md, and the policy lint
      will report `contradiction` until the rule is gone
```

Default is **no**. Removing a line from a file the user wrote is a destructive edit, so init only *offers* it: **never remove it silently, and never remove more than the one line that was shown.**

**On `[n]`, record `tracked-md` anyway** and say plainly, in the step-6 report, that the lint will report `contradiction` and what closes it. The declaration is the user's intent; quietly downgrading it to match a rule they chose to keep would hide the disagreement, and surfacing exactly this disagreement is what the lint is for.

**c. Write `.epico/.gitpolicy`** — line 1 is the declaration, and it is the only line any tool reads:

```
tracked-md
# Epico versioning policy — line 1 is the declaration and the only line read.
# Written by /epico:epico init; re-run init to change it.
# Docs: references/init-mode.md#versioning-policy
```

### Step 5.4 — Local-only → `local-only`

**a. Ensure the *root* `.gitignore` ignores `.epico/`.**

| `gitignore_ignores_epico` | `gitignore_source` | What init does |
|---|---|---|
| `true` | `.gitignore` | Nothing. The root file already carries the rule |
| `true` | `.git/info/exclude` or any other path | **Append the rule to the root `.gitignore` anyway.** Neither `.git/info/exclude` nor a global `core.excludesFile` travels with the repository — a teammate who clones it has nothing ignoring `.epico/`. That is why the rule must live in the root file |
| `false` | `null` | Append the rule |
| — | absent (`git: false`) | Append the rule. It costs nothing and takes effect the moment the directory becomes a repository |

**Before appending, disclose what the rule would strand.** The append writes a rule; it untracks nothing, and git will not untrack anything either. So in a repository that already tracks artifacts the rule leaves those files committed under a line saying they never are — `verdict: contradiction`, the lint's first arm, manufactured by the wizard that exists to prevent it. Read `tracked_md` from the step 5.1 measurement already in hand — only when `git` is `true`, per the read-order contract there — and add `tracked_draft` to it when that is non-zero, because the arm counts both. At `0`, append with no prompt: nothing can be stranded, and a question that always answers itself is one people learn to click through. Above `0`, ask first, quoting the count:

```
This repository already tracks 23 .epico artifacts.

Local-only adds .epico/ to the root .gitignore. Git will not untrack those 23
files, so they stay committed under a rule that says they never are — the
policy lint calls that `contradiction`. Add the rule anyway?
  [y] add it — the 23 files stay tracked, and the lint reports `contradiction`
      until you untrack them yourself with `git rm -r --cached .epico`;
      init never runs that command
  [n] skip the rule — local-only is still recorded, and the lint reports
      `partial`: declared local-only, artifacts tracked anyway
```

Default is **no**, and `[n]` still runs step b. The declaration is the user's answer to step 5.2 and is recorded either way; what `[n]` declines is the *rule*, leaving a `partial` that names the disagreement rather than a `contradiction` that adds one. Where the root file already carries the rule, init appends nothing and never reaches this prompt. Where `gitignore_source` is `.git/info/exclude` or a global file, the `contradiction` predates init — step 5.1 has already shown it and `[n]` cannot lower it — but the prompt still fires, because appending to the *root* file is what makes that state travel to every clone.

**This is step 5.5's reasoning on the other path.** A headless run must not reverse a declaration nobody watched it reverse; an interactive one must not strand the files a declaration is being made about. Both refuse to manufacture the same shape — one by declining to act, the other by asking first.

Appended block, when the file already exists:

```gitignore

# Epico artifacts stay local to this machine (policy: local-only, see .epico/.gitpolicy)
.epico/
```

**Ensure the file ends with a newline before appending**, or the comment splices onto whatever pattern was last in the file and silently changes what that pattern matches. When `.gitignore` does not exist, create it with the same two lines and no leading blank line.

**b. Write `.epico/.gitpolicy`** with the same footer as step 5.3c and `local-only` on line 1:

```
local-only
# Epico versioning policy — line 1 is the declaration and the only line read.
# Written by /epico:epico init; re-run init to change it.
# Docs: references/init-mode.md#versioning-policy
```

**c. Do not write `.epico/.gitignore` in this branch.** Under local-only the whole directory is excluded, so a nested ignore file inside it can never change what git does — it would be a generated file with no effect. An `.epico/.gitignore` left over from an earlier run is **kept, never deleted**: it is equally inert, and deleting a user's file to tidy up is not this wizard's business.

### Step 5.5 — Non-interactive init

**A headless run applies local-only, prompts for nothing, and never starts tracking.**

Detect the session kind with the signal the skill already defines — `AskUserQuestion` callable means an interactive session, otherwise the run is headless or Agent SDK (see the Runtime dependency precheck in [triage.md](triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage)). This is the same signal, read the same way, that [preferred-tooling.md](preferred-tooling.md) and [validate-mode.md](validate-mode.md#headless) use for their own pauses. Do not invent a second detection.

| `policy` reported by the lint | Headless init does |
|---|---|
| `undeclared` | Apply step 5.4 in full — root `.gitignore` rule, then `local-only` in `.epico/.gitpolicy` |
| `local-only` | Re-run step 5.4a only (idempotent: it appends nothing when the root file already carries the rule). Leave the policy file as it is |
| `tracked-md` | **Change nothing.** Log the detected policy and move on |

That last row is the one to get right. Overwriting a recorded `tracked-md` would reverse a decision the user made out loud, and adding `.epico/` to the root `.gitignore` of a repository that already tracks artifacts manufactures the contradiction — tracked files under an ignoring `.gitignore` — in a run nobody was watching. The conservative default is for a workspace that has said nothing; it is not a licence to overrule one that has.

Emit the outcome as a logged note, never a pause:

```
Epico versioning policy: local-only applied (non-interactive run — the conservative
default; nothing under .epico/ will be committed). Run `/epico:epico init` in an
interactive session to choose versioned artifacts instead.
```

### After init — making a `tracked-md` declaration real

Init records the intent; it does not stage or commit anything (the Rules above: init writes files and nothing else). So immediately after a versioned init the lint reports **`partial`** — "declared tracking that never happened", because `.epico/.gitpolicy` says `tracked-md` while every artifact is still untracked. That is correct, and one commit settles it. Close the step-6 report with the command that does:

```
git add .epico && git commit -m "chore: track .epico artifacts (policy: tracked-md)"
```

The verdict goes to `consistent` on the next run of the lint. Local-only reaches `consistent` with no follow-up: nothing is expected to be tracked, and nothing is.
