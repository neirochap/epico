---
story: 030-validation-result-reuse
type: feature
scale: full
engineering: project
version: 1
created: 2026-11-04
status: draft
---

# Design - Validation Result Reuse

## Overview

Today every check runs again, even when the code it reads has not changed. The same validation command can run up to seven times in one story: Executor step 4, Executor step 5, the end-of-run gates, `epico-validate-run`, the Auditor's reproductions, a fix round, and pre-commit. This story adds **exact reuse**: a check whose command, code fingerprint and environment key equal those of its last PASS is not run again. It also fixes the `--only` bug that drops entries from the report, and rewrites the gate guidance that forces suites into one command.

Key decisions:
- **One script owns the run.** `scripts/check-reuse.sh` behind `bin/epico-check`. It is the only writer of the ledger.
- **Shared ledger.** The ledger lives in the git common dir, so every worktree of a repository shares it.
- **Per-project profile.** `.epico/reuse-profile.json` adds tool versions and ignored inputs to the key, lists the commands never reused, and holds the mode switch.
- **Shadow is the default mode.** Nothing is reused until a person switches the project to `on`.

Evidence (benchmark 2026-11-02 on a pnpm/turbo monorepo, 13 gates, 5 injected-failure scenarios): total 147 → 46 min. Exact reuse alone removed 47.9 min. Fingerprint cost was 8–20 ms on five repositories of 881–5256 tracked files, across Node/turbo, Go, Prisma, a serverless worker with a PHP plugin, and Makefile/mutation testing.

**Project-agnostic by rule.** Nothing this story ships — code, references, agent text, tests or examples — names a real project. The Epico analyses each project on its own (the profile is detected per repository), and its stored instructions describe *cases* ("a gitignored `.epico/` holding a tracked file"), never *projects*. The evidence above is described the same way.

## Architecture

```mermaid
flowchart LR
  subgraph callers [Callers]
    VR[validate-run.sh]
    EX[Executor step 4/5]
    IN[Inline route / end-of-run gates]
    AU[Auditor Part 2 reproductions]
    LR[Lean route whole check]
  end
  CR[check-reuse.sh<br/>bin/epico-check]
  PF[(.epico/reuse-profile.json)]
  LG[(git-common-dir/epico/reuse/ledger.json)]
  SH[(git-common-dir/epico/reuse/shadow.log)]
  HK[hook-reuse-guard.sh<br/>PreToolUse]
  VR --> CR
  EX --> CR
  IN --> CR
  AU --> CR
  LR --> CR
  CR --> PF
  CR --> LG
  CR --> SH
  HK -. denies agent writes .-> LG
```

Some callers keep running their command directly and **never** route through `epico-check`:
- the Test Advisor's Red runs (`agents/test-advisor.md`, "Red" verification);
- the deferred E2E Red run before the Executor (`references/run-mode.md`, Deferred E2E);
- the Auditor's bugfix "guard must bite" on the base commit (`agents/auditor.md`);
- the final reviewer's clean-copy run (`agents/final-reviewer.md`, the `mktemp -d` copy).

A run that must see a FAIL, or must run somewhere other than the working tree, is the opposite of a reusable PASS.

## Components & Interfaces

### check-reuse.sh (`bin/epico-check`)

- **Responsibility:**
  - compute the reuse key;
  - look up the ledger and decide `ran` | `reused`;
  - run the command with validate-run's semantics: own session, timeout, process-group kill, last-line evidence;
  - record the result in the ledger, and in shadow mode append one line to `shadow.log`.
- **Interface** — one JSON line on stdout, diagnostics on stderr. Exit 0 = PASS (run or reused), 1 = FAIL, 2 = bad usage. Usage errors print no JSON (`close-subtask.sh` convention).

| Subcommand | Purpose | Output (JSON keys) |
|---|---|---|
| `run [--fresh] [--timeout <s>] -- <command>` | Decide, run or reuse, record | `mode`, `decision` (`ran`\|`reused`), `would_reuse` (bool), `result` (`PASS`\|`FAIL`), `exit`, `evidence`, `secs`, `fingerprint` (string\|null), `key` (string\|null), `reason` |
| `lookup -- <command>` | Report what `run` would decide, running nothing. `validate-run.sh` reads `fingerprint`; `last` is for a person diagnosing a decision | `mode`, `would_reuse`, `fingerprint`, `key`, `last` (ledger entry\|null), `reason` |
| `stats` | Summarise shadow.log | `runs`, `would_reuse`, `agreed`, `disagreed` (list of `{command, at}` — `at` is a UTC timestamp), `secs_reusable` |
| `profile --detect` | Print a proposed profile; writes nothing | the profile object |

- **There is deliberately no `record` subcommand.** A result enters the ledger only as the outcome of a `run`, so no caller can write a PASS it did not run.
- **Dependencies:** bash, jq, git, plus `setsid` and `timeout`, which validate-run.sh already uses.

### Reuse key

`key = git hash-object --stdin` of a canonical JSON document, with these fields:
- `command`: the exact command string;
- `tree`: the fingerprint below;
- `tools`: one `{probe, output}` per profile probe, with the probe's stdout+stderr, or `absent` when the binary is not on PATH;
- `inputs`: one `{path, blob}` per profile input, where `blob` is `git hash-object --no-filters -- <path>`, or `absent`;
- `profile`: the hash of the profile file itself, so editing the profile invalidates every key.

**Fingerprint:**
1. Copy the real index (`git rev-parse --git-path index`) to a temp file.
2. `GIT_INDEX_FILE=<temp> git add -A -- .`
3. `git rm -r -q --cached --ignore-unmatch -- .epico .epic`
4. `git write-tree`
5. Delete the temp file.

**No fingerprint is produced** for:
- a directory that is not a git work tree;
- any failure of steps 1–4 (an unreadable file, for example);
- a submodule with uncommitted content (`git status --porcelain --ignore-submodules=none` reporting it).

With no fingerprint, `run` runs the command and records nothing reusable.

**The fingerprint is always reported when it can be computed**, in every mode and for never-list commands too. Not writing to the ledger is a separate decision. `validate-run.sh --only` relies on the fingerprint to keep an unchanged PASS, so a row that skips it would make `--only` re-run unchanged entries.

**Probes and inputs:**
- Each probe runs under `timeout "${EPICO_REUSE_PROBE_TIMEOUT:-10}" bash -c "<probe>"`. Its output is captured even when it exits non-zero; `java -version`, for one, prints to stderr.
- A probe that times out gives **no key**, with a reason naming the probe. The command still runs.
- A profile input that exists but is a directory or unreadable gives **no key**, with a reason naming the input. The command still runs.
- In both cases a stable placeholder would hide a real change, so no key is safer than a wrong one.

### Decision table (`run`)

The `fingerprint` key in the output is filled whenever it can be computed, in every row (see above).

| Mode | Fingerprint | Ledger has PASS for key | Command in `never` | `--fresh` | Decision | Ledger write | shadow.log |
|---|---|---|---|---|---|---|---|
| `off` | — | — | — | — | ran | no | no |
| any | none | — | — | — | ran | no | no |
| any | yes | — | yes | — | ran | no | no |
| `shadow` | yes | yes/no | no | no | ran (`would_reuse` = ledger hit) | yes | yes |
| `on` | yes | yes | no | no | **reused** | no | no |
| `on` | yes | no | no | no | ran | yes | no |
| `shadow`/`on` | yes | — | no | yes | ran | yes (overwrites) | shadow only |

**Only a PASS is ever a hit.** A FAIL is recorded so `stats` can count disagreements, but it is never reused.

### reuse-profile.json

- **Responsibility:** the per-project reuse configuration, reviewable by a person.
- **Format: JSON, not YAML.** jq is the only parser the constitution allows.
- **Shape:** `{"version": 1, "mode": "shadow", "tools": ["node --version", "pnpm --version"], "inputs": ["apps/api/.env.test"], "never": ["scripts/ci-local.sh --only <job-that-needs-real-credentials>"]}` (placeholder shown here only; a real profile holds real command substrings).
- **`never` entries are literal substrings** of the command.
- **Absent file:** `mode` = `shadow` and empty lists. Every JSON output carries `reason: "profile absent"`.
- **Invalid JSON:** treated as absent, with a stderr warning. Never a crash.
- **`--detect`** proposes a profile and writes nothing:
  - **`tools`**, from the manifests present, and only for binaries on PATH:
    - `package.json` → `node --version` plus the `packageManager` tool's `--version`;
    - `go.mod` → `go version`;
    - `Cargo.toml` → `rustc --version`;
    - `pyproject.toml`/`requirements*.txt` → `python3 --version`;
    - `composer.json` → `php --version`;
    - `build.gradle*`/`pom.xml` → `java -version`;
    - `Gemfile` → `ruby --version`;
    - `deno.json*` → `deno --version`.
  - **`inputs`**: gitignored files named `.env`, `.env.*`, `.dev.vars` or `*.local.{json,yaml,yml,toml,php}`, outside `node_modules/` and `vendor/`.
  - **`never`**: left empty. Which commands need credentials, docker or a live service is a judgement made at init, not detected.

### Ledger and shadow log

- **Location:** `$(git rev-parse --path-format=absolute --git-common-dir)/epico/reuse/`.
- **`ledger.json`:** `{"version": 1, "entries": {key: {command, result, fingerprint, at, secs}}}`, capped at **2000 entries**; the oldest `at` is dropped first.
- **An unreadable ledger** — invalid JSON, a wrong shape, or a `version` other than 1 — is never overwritten in place. It is renamed to `ledger.json.unreadable-<UTC timestamp>`, a name that never replaces an earlier set-aside copy, and a fresh ledger starts empty.
- **`shadow.log`:** JSON lines `{at, command, key, would_reuse, result, secs}`, capped at **5000 lines**; the oldest are dropped first.
- **Every write** goes to a temp file in the same directory, followed by `mv`.

### validate-run.sh (changed)

- **P0:** `--only` with no previous `validation-run.json` exits 2: `validate-run.sh: --only needs a previous full run; run without --only first`.
- **Each runnable entry runs through `check-reuse.sh run --timeout "$TIMEOUT"`**, called by path. A script-to-script call, as validate-run already calls nothing through a wrapper. Its own `run_cmd`/`runner_totals` move into check-reuse.sh unchanged.
- **Entry JSON gains `reused` (bool) and `fingerprint` (string|null).** Both are additive. `kind`, `id`, `result`, `qualifier` and `detail` are unchanged. The YAML report gains **only** `reused:` on each result and gate; the fingerprint stays in the JSON, its only reader.
- **An unusable `lookup`** (non-zero exit, no JSON or invalid JSON) counts as an unknown fingerprint, and the entry is re-run.
- **Under `--only`:**
  - an unselected previous entry whose `result` is PASS is kept **only if** its `fingerprint` equals the current one;
  - otherwise it is re-run;
  - an entry with no `fingerprint` (a pre-030 report) is re-run;
  - SKIP and JUDGE entries are kept as today.
- **`--fresh`** is passed through to every `run`.

### hook-reuse-guard.sh (new, PreToolUse)

- **`Edit|Write`:** deny when `tool_input.file_path` resolves inside `<git-common-dir>/epico/reuse/`.
- **`Bash`:** deny a command that names that directory and holds a redirection or `mv`/`cp`/`tee`/`rm` into it, **whatever else it runs**. There is no exemption for a command that also calls `epico-check`. The runner writes the ledger itself, never through the text of an agent's command, so it needs none, and an exemption would let `cp forged.json <dir>/ledger.json && epico-check stats` through.
- **Fails open on its own error** (constitution, Architecture).
- **The deny message** names the rule: the ledger is written only by `epico-check run`.

### Reference: check-reuse.md (new)

- **The single home of the reuse rules:** which callers route through `epico-check`, which never do and why, the modes, and how to read `epico-check stats`.
- **Short pointers to it,** because run-mode.md is at 489 of the 500 lines `tests/file-size.bats` allows:
  - `agents/executor.md` steps 4 and 5;
  - `agents/auditor.md` Part 2;
  - `references/run-mode.md` (inline route, end-of-run gates);
  - `references/lean-route.md`;
  - `references/validate-mode.md`.
- `references/init-mode.md` calls `epico-check profile --detect` directly (see "init / doctor"), so it needs no pointer.

### Gate guidance (P3)

- **`quality-catalog.md:106`** (the sentence beginning "The first backtick span of a gate is the whole command validate runs"): the "one command that loops over them — `for t in a b; …`" clause becomes **one gate line per target, sharing the legend's `Qn`, each with a distinct text prefix** — `- [ ] Q5 — Unit tests (api): …`, `- [ ] Q5 — Unit tests (checkout): …`. Per-target lines are what can be reused one by one, and `close-subtask.sh` already refuses an ambiguous `gate:` prefix (`record_candidate` counts every match).
- **`tasks.md:273`** ("one box per line of the story's `## Quality Requirements` legend") becomes "one or more boxes per legend line — one per target".
- **New subsection in quality-catalog.md:**
  - **Never switch a tool's own cache off in a gate:** turbo `TURBO_FORCE`/`--force`, nx `--skip-nx-cache`, jest `--no-cache`, pytest `--cache-clear`, gradle `--rerun-tasks`/`--no-build-cache`.
  - **`go test -count=1` only for tests that read external state** (a database, the network).
  - **Prefer incremental modes**, such as Stryker `incremental`.
  - **Never write a gate whose command already runs another gate's command.** For example, a `make test` target that already runs the unit suite, beside a `make test-unit` gate that runs it again.
  - **No project names in the guidance.** Every example is generic.

### init / doctor (changed)

- **`init`** (and `init --repair`) runs `epico-check profile --detect`, shows the proposal in one line, and writes `.epico/reuse-profile.json` with `mode: shadow`. The requester adds `never` entries at that point.
- **`doctor.sh --summary`** warns `no reuse profile — run /epico:epico init --repair` when `.epico/` exists without one.

## Data Models

```mermaid
erDiagram
  PROFILE ||--o{ KEY : "tools, inputs, own hash feed"
  KEY ||--o| LEDGER_ENTRY : "last result for"
  KEY ||--o{ SHADOW_LINE : "one per shadow run"
  PROFILE { int version string mode list tools list inputs list never }
  KEY { string command string tree list tools list inputs string profile }
  LEDGER { int version map entries }
  LEDGER ||--o{ LEDGER_ENTRY : "entries"
  LEDGER_ENTRY { string command string result string fingerprint string at int secs }
  SHADOW_LINE { string at string command string key bool would_reuse string result int secs }
```

## Sequence Diagrams

```mermaid
sequenceDiagram
  participant C as Caller (validate-run / agent)
  participant R as check-reuse.sh run
  participant G as git
  participant L as ledger.json
  C->>R: run --timeout 300 -- "<cmd>"
  R->>R: load profile (absent → shadow defaults)
  R->>G: copy index, add -A, rm --cached .epico .epic, write-tree
  G-->>R: tree (or failure → no fingerprint)
  R->>R: key = hash(command, tree, probes, input blobs, profile hash) — none if no tree, a probe timed out or an input is unreadable
  alt mode off, or cmd in never, or no key
    R->>R: run cmd
    R-->>C: {decision: ran, fingerprint (when computed), reason}
  else
    R->>L: lookup key
    alt mode on and PASS hit
      R-->>C: {decision: reused, result: PASS}
    else
      R->>R: run cmd (setsid, timeout, group kill)
      R->>L: write {result, fingerprint, at, secs} (temp + mv)
      R->>R: shadow? append shadow.log line (capped)
      R-->>C: {decision: ran, would_reuse, result}
    end
  end
```

## Error Handling Strategy

- **Not a git repo, git failure, unreadable file, dirty submodule:** no fingerprint. The command runs, `reason` names the cause, nothing reusable is recorded.
- **Profile invalid JSON or unknown `version`:** treated as absent, with a stderr warning. The profile is never modified by `epico-check`. A missing probe binary gives `absent` in the key, which stays stable.
- **Ledger unreadable** (invalid JSON, wrong shape, unknown `version`): set aside under a timestamped name, never overwritten; reuse restarts from an empty ledger, which only costs runs.
- **Ledger or shadow.log write failure:** stderr warning. The command's result is still returned and the exit code is the command's. Reuse is an optimisation, never a reason to fail a check. Every write and every `mkdir` of the reuse directory is called with its error handled; none relies on `set -e`.
- **Setting an unreadable ledger aside fails** (read-only directory): stderr warning; the check runs as if nothing were recorded.
- **A probe times out, or an input is unreadable:** no key, with a reason; the command runs.
- **`profile --detect` meets a malformed manifest or no git work tree:** it skips what it cannot read (the `packageManager` probe; the inputs), warns, and still prints a profile with exit 0.
- **`lookup` is unusable inside `validate-run.sh --only`:** the entry is re-run.
- **Lost update** (two writers at once): the second `mv` wins. The lost entry costs one re-run, which is the safe direction.
- **Timeout:** exit 124, mapped to FAIL with evidence `timed out after <s>s`, as validate-run does today.
- **Hook failure:** fail open.

## Security Considerations

- **Forged PASS:** there is no `record` subcommand; the hook denies every agent write into the ledger directory, with no exemption; a `run` records only what it ran. Residual: a caller can still run a different command that passes, which records a PASS for *that* command only. The Bash check is pattern-based, so an obfuscated write (a variable holding the path) can slip past it.
- **Secrets:** `inputs` enter the key as git blob hashes. Their content is never stored. The ledger stores command strings, so a gate that embeds a token in its command stores it under `.git/` (never committed). check-reuse.md says to keep secrets out of gate commands.
- **Ledger location:** under the git dir, so it is never committed and never part of the fingerprint.

## Performance Considerations

- **Fingerprint:** 8–20 ms measured on 881–5256 tracked files. Copying the real index keeps git's stat cache; an empty temp index would re-hash every file.
- **Probes:** one process each, computed once per `run`.
- **Ledger:** bounded at 2000 entries and shadow.log at 5000 lines, so jq reads stay small.
- **Loose objects:** `git add` on the temp index writes blobs for changed and untracked files. They are unreferenced, and `git gc` prunes them. The script never runs gc.

## Testing Strategy

- **Unit tests** (bats, one file per sub-task: `tests/check-reuse-{fingerprint,key,run,ledger,shadow,profile}.bats`):
  - **Fingerprint across `.epico` states:** versioned, gitignored, gitignored-with-a-tracked-file.
  - **Fingerprint absent:** non-git dir, dirty submodule.
  - **Key changes** when an `inputs` file changes, when a probe's output changes, and when the profile changes.
  - **Decisions:** the decision table rows (off, shadow, on hit/miss, never, `--fresh`, FAIL never reused).
  - **Caps:** ledger cap 2000, shadow.log cap 5000.
  - **Contract:** usage errors exit 2 with no JSON; JSON contract keys.
  - **`profile --detect`** on fixture manifests.
  - **`stats`** counts.
- **Integration tests** (bats, real temp git repos):
  - **validate-run.sh:**
    - `--only` with no prior run exits 2;
    - `--only` keeps a PASS only when its fingerprint is unchanged and re-runs it otherwise;
    - a pre-030 report entry is re-run;
    - `reused`/`fingerprint` appear in the JSON, and `reused:` in the YAML.
  - **Readers unchanged:** `run-report.sh`, `report.sh` and `checkbox-grammar.bats` still pass.
  - **Guard:** `hook-reuse-guard.sh` denies Edit/Write and redirecting Bash into the ledger dir, and allows everything else.
  - **Gates:** a story with two `Q5 — …` gate lines validates clean, and `close-subtask.sh` closes each by its distinct prefix.
  - **Wrappers:** `bin-wrappers.bats` lists `check`.
  - **Worktrees:** a run in a linked worktree hits the PASS recorded in the main one.
- **E2E tests:** none (tool: `none`). A bash plugin with no UI.

## Tooling Decisions

- E2E tool: none — not applicable (bash plugin, no UI)
- Frontend aid: none
- Recommendation surfaced: no

## Integration Points

- **`scripts/validate-run.sh`:**
  - `:109-127`: `run_cmd`, with the comment "Output goes to a file, not a pipe";
  - `:132-138`: `runner_totals`, which moves to check-reuse.sh;
  - `:150-172`: `check()`, which calls `check-reuse.sh run`;
  - `:174-179`: the `PREV='[]'` / `--only` merge, the P0 fix;
  - `:193-209`: the JSON and YAML writers, which gain the new fields.
- **Readers of `validation-run.json` / `validation-report.yaml`:** `scripts/run-report.sh:8`, `scripts/report.sh`, `tests/checkbox-grammar.bats:588`. Fields are additive only.
- **`tests/fast-verification.bats`:** `setup()` `:11-65`, the `--only` case `:108-118`, and the six cases calling `--only` with no prior run (`:122, :198, :210, :225, :232, :240`). Each gets a full run first.
- **`tests/bin-wrappers.bats:19`** (the hand-kept wrapper list) gains `check`. `\bepico-check\b` does not match `epico-checkpoint`.
- **Wrapper pattern:** `bin/epico-validate-run`'s `exec bash "$(dirname "$0")/../scripts/<x>.sh" "$@"`.
- **`hooks/hooks.json` PreToolUse:** add `hook-reuse-guard.sh` to the `Edit|Write` and `Bash` matchers, beside `hook-executor-guard.sh`.
- **Callers to route** (pointers to check-reuse.md):
  - `agents/executor.md:94` (step 4 "Run the Validation command") and `:100` (Refactor re-runs);
  - `agents/auditor.md` Part 2 claim reproduction;
  - `references/run-mode.md` inline route `:130-150` and end-of-run gates `:468`;
  - `references/lean-route.md:37` (the whole check);
  - `references/validate-mode.md:177` (step 3) and `:195` (`--only` revalidation).
- **Callers that must not route:**
  - `agents/test-advisor.md` Red runs;
  - `references/run-mode.md:281` (deferred E2E Red);
  - `agents/auditor.md:39` (bugfix guard on the base commit);
  - `agents/final-reviewer.md:24-26` (clean copy).
- **Guidance:** `references/quality-catalog.md:106` and `references/tasks.md:273`.
- **Init and doctor:** `references/init-mode.md` (profile written at init) and `scripts/doctor.sh` (summary warning).
- **Size guard:** `tests/file-size.bats:12` (500-line limit; run-mode.md 489, validate-mode.md 421).

## Implementation Gotchas

- **GOTCHA: git exclude pathspec** — `git add -A -- . ':(exclude).epico'` exits 1 ("paths are ignored by one of your .gitignore files") when `.epico/` is gitignored. Measured on a real project. **Fix:** add everything, then `git rm -r -q --cached --ignore-unmatch -- .epico .epic` on the temp index.
- **GOTCHA: git check-ignore** — reports a gitignored directory that holds a tracked file as *not* ignored. Seen in a real project: one archived `tasks.md` was tracked under an ignored `.epico/`. **Fix:** never branch on check-ignore; the removal above covers every state.
- **GOTCHA: temp index** — an empty `GIT_INDEX_FILE` re-hashes the whole tree. **Fix:** start from a copy of `git rev-parse --git-path index` (worktree-aware), which keeps the stat cache. That is what gave 8–20 ms.
- **GOTCHA: git common dir** — `git rev-parse --git-common-dir` is relative (`.git`) in the main worktree and absolute in linked ones. **Fix:** use `--path-format=absolute` (git ≥ 2.31; 2.56 here).
- **GOTCHA: submodules** — `git add -A` records a submodule's commit, not its uncommitted changes, so a dirty submodule would fingerprint as clean. **Fix:** detect it through `git status --porcelain --ignore-submodules=none` and produce no fingerprint.
- **GOTCHA: hashing inputs** — `sha256sum` is GNU, macOS ships `shasum`. **Fix:** use `git hash-object --no-filters -- <path>`, which is git-only, portable, and writes no object without `-w`.
- **GOTCHA: timing** — `date +%s%N` is unsupported on macOS. **Fix:** measure with bash `SECONDS` and stamp with `date -u +%Y-%m-%dT%H:%M:%SZ`.
- **GOTCHA: concurrent writers** — parallel Executors in worktrees write the same ledger. flock is util-linux, outside the constitution's bash+jq+git, and absent on macOS. **Fix:** write a temp file in the same directory, then `mv`, so the file is never torn. A lost update costs a re-run.
- **GOTCHA: moving validate-run's run semantics** — they must move intact (`setsid --fork --wait`, `timeout`, process-group kill, output to a file, not a pipe). validate-run.sh's own comment records a `cargo run &` holding a pipe open until the timeout (300 s lost).
- **GOTCHA: profile format** — YAML would need yq, which the constitution does not allow. **Fix:** the profile is JSON.
- **GOTCHA: ambiguous gate prefix** — two `Q5` lines are closed by `gate:<prefix>`. **Fix:** the prefixes must differ before the colon (`(api)`, `(checkout)`), or `close-subtask.sh` refuses the ambiguous match.
- **GOTCHA: run-mode.md size** — 489/500 lines. **Fix:** new prose goes to `references/check-reuse.md`; run-mode.md gets one pointer line per routed step.
- **GOTCHA: flaky checks pollute shadow numbers** — in the benchmark, an integration suite was red 2 of 3 times on a clean main branch. **Fix:** `stats` reports "would reuse a PASS, ran FAIL" as a *disagreement*, never as a false green. A person reads the list before switching to `on`.
- **GOTCHA: cache-flag detection** — `--no-cache` on `apk add` is not a test cache. **Fix:** the catalog's guidance names tool and flag together, never a bare flag.
