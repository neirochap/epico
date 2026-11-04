# Quality Catalog

The checks a piece of software is expected to carry, in three tiers, and how the Epico decides which of them a story activates. It is the source that the `## Quality` block of the constitution ([init-mode.md](init-mode.md)), the `## Quality Requirements` legend of a story ([requirements.md](requirements.md)) and the generated Quality Gates of `tasks.md` ([tasks.md](tasks.md#generated-quality-gates)) all draw from: each names an item by its row here.

## How the set is chosen

1. **The constitution's `## Quality` block** is the project's default legend: the always tier, plus the context items init's scan detected. Written once by init, read by every story.
2. **The Analyst's scan** ([analyst.md](../agents/analyst.md)) reports which context signals the tree carries — a `Dockerfile`, a `.github/workflows/` directory, a database configuration, an HTTP surface, a UI — and which always-tier tools the tree is already configured for.
3. **The request** adds what the constitution could not know: an API consumed by more than one client activates contract tests; a stated performance requirement activates a benchmark.
4. **The story's legend** is the result: `## Quality Requirements`, one line per active item, numbered `Q1`…`Qn` in the order of this catalog, each with the command that proves it on this project. A Fast story, which has no `story.md`, carries the legend at the top of `tasks.md`.

**The engineering level bounds the set** ([engineering-level.md](engineering-level.md)): `experiment` activates the **security floor** below and nothing else; `tool` activates the always tier; `project` adds every context item whose signal the tree or the request carries; `product` adds the CI-shaped context items — hardened workflows, the CI mirror, minimum dependency age, licence, SBOM and signing, security policy and branch protection — without waiting for a signal, and the on-request tier when a requirement names it. The four steps above choose inside that bound.

**Activating an item never installs a tool.** The [preferred-tooling policy](preferred-tooling.md) applies: prefer the tool already installed for that item, name a recommendation and pause when none is, and record the choice on the legend line. A layperson is never paused for a tool choice — the best installed tool is taken and recorded.

## Always

Cheap, universal, and each provable by one command. A story that leaves one out says why on its legend.

| Item | What it proves | Typical command |
|---|---|---|
| Formatting | one style, applied by a tool, never by hand | `gofmt -l .` · `prettier --check <source dirs and files>` · `ruff format --check` · `cargo fmt --check` |
| Lint | probable defects and known bad practice are absent | `golangci-lint run` · `eslint .` · `ruff check` · `cargo clippy` · `shellcheck` |
| Types | the program type-checks; a dynamic language carries annotations and a checker | `tsc --noEmit` (strict) · `mypy` · the compiler, for Go and Rust |
| Error handling | every error carries context and none is swallowed | the story's tests; a grep for bare `catch {}`, `_ = err`, `except: pass` |
| Unit tests | each unit of logic has a test, written first | `go test ./...` · `npm test` · `pytest` · `cargo test` · `bats tests/` |
| Lockfile and frozen install | the same dependency versions on every machine | `npm ci` · `--frozen-lockfile` · `pip install --require-hashes` · `go mod verify` |
| Dependency vulnerabilities | no known CVE in the dependency list (SCA) — **a project with no dependencies satisfies this item**: zero dependencies is zero CVEs | `trivy fs .` · `osv-scanner .` · `cargo audit` · `govulncheck ./...` |
| Secrets | no credential in the tree or the history — checked before the commit exists, and again in CI | `gitleaks detect` (pre-commit) · `trufflehog git file://.` (CI side, verifies which secrets are live) |
| README | how to run and how to test, in the repository | the two commands the README names exist and run |
| `.gitignore` and `.editorconfig` | generated files stay out; indentation is agreed | both files exist; `git status --short` is clean after a build |
| Supported and declared runtime | the runtime is a supported release with no known vulnerability — an LTS or the current widely-used stable, **whichever is clean** — and the project declares it where a tool reads it: `engines` in `package.json`, the `go` directive of `go.mod`, `requires-python` in `pyproject.toml`, `rust-version` in `Cargo.toml`, `ruby` in the `Gemfile` or `.ruby-version`, `require.php` in `composer.json`, or `.tool-versions` for any of them. A Rust `edition` is a language dialect, not a minimum compiler; a version named only in the README is read by people, not by tools | the declaration exists where a tool reads it and names a supported version — never only `node --version`, which proves what is installed, not what is declared; a single script with no manifest declares in `.tool-versions` |
| Dependencies justified and current | every dependency has a one-line reason the standard library or the code already there was not enough, recorded where the choice was made, and is a current release | the manifest's list against the story's `## Constraints` or the design's decisions; `npm outdated` · `go list -m -u all` · `pip list --outdated` |

### The security floor — five items no level drops

**`experiment` is the only level that activates nothing else, and it still activates these five.** A throwaway is thrown away; the machine it ran on is not, neither is the account whose token it carried, and neither is what the person typed into it.

| Floor item | Why it survives every level | Typical command |
|---|---|---|
| Supported and declared runtime | a program is only as safe as the interpreter under it — a hello world on an end-of-life runtime is vulnerable before its first line, because the environment is the hole. **Prefer the LTS; take the current widely-used stable instead when the LTS is the one carrying a known vulnerability** | the **declaration** exists where a tool reads it — `jq -e .engines package.json`, the `go` line of `go.mod`, `requires-python`, `rust-version`, `.tool-versions` for a single script with no manifest — and names a supported version; `node --version` alone proves what is installed here, not what the project declares. Then the CVE scanner against that version |
| Secrets | a credential leaked from a script leaks exactly as far as one leaked from a product | `gitleaks detect` |
| README | a program nobody can run is not a program you can "go on using exactly as it is" — the level's own promise. Two lines: how to run it, how to check it | the commands the README names exist and run |
| Dependency vulnerabilities (SCA) | a malicious or vulnerable package does not ask what the project's engineering level is | `trivy fs .` · `cargo audit` · `govulncheck ./...` — see the empty-manifest note below |
| Data integrity | a throwaway still holds the user's data. A save file that a crash truncates, or that a corrupted read silently replaces with an empty list and writes back, loses what the person typed — the one loss `experiment` never promised | when the program writes a file it reads back: the story's tests prove the write goes through a temporary file renamed over the target, and that a missing file and a corrupted file each start the program without a crash and without overwriting the original. A file that parses but has the wrong shape counts as corrupted; a corrupted file set aside never replaces an earlier one (a timestamped name, not a fixed `.corrupt`); and a save that fails says so instead of reporting success. With no such file, the gate records `no persisted data` |

**No dependencies is a verdict, not a failure.** A project that declares none satisfies the SCA item outright, and that is the *common* case at `experiment`, not the exception. Some scanners disagree with their own exit code: `osv-scanner .` on a zero-dependency Node project exits **128** with `no package sources found` — an error, where the honest answer is "nothing to report". Pick a tool that gives the verdict (`trivy fs .` does), or record `no dependencies` as the result and move on. **A story is never failed for having nothing to scan.** The same holds for data integrity: a program that writes no file it reads back records `no persisted data` on the gate, and that is the answer.

The five are chosen as much for their price as for their weight: **one command, one file or a few tests each, no checker configuration, seconds to run.** A floor that cost minutes would be argued with; this one is cheaper than the argument. Data integrity is proved by tests the plan writes anyway — a rename instead of an overwrite, two start-up cases. The README is the only one that is written rather than run, and it is here for the same reason as the rest: `experiment` promises the thing stays usable as it is, and a program whose run command lives only in a chat transcript does not.

**The floor is checked, not asked for.** `validate-story.sh` reads the Quality Gates section of `tasks.md` and reports, as an **error**, every floor item that has no gate — so a story that skipped one fails validation instead of passing quietly. It matches the item's name, never a particular command, because the command is the project's own: `trivy fs .`, `cargo audit` and `govulncheck ./...` all prove the SCA item. The check is gated on a declared `engineering:` level, this file's rule for every field the plugin added rather than inherited — fail-open on absence, fail-closed on a value present — so a story with no declared `engineering:` level validates exactly as before. Without the check, a story that drops floor items — even several at once — validates clean. A floor nothing verifies is a request.

Everything else in this catalog stays bound by the level.

**At `tool`, the tier is paid with defaults — no configuration file.** Every always item stays active, and every one is proved by **one command**: whatever the checker needs rides on the command line (`npx tsc --noEmit --allowJs --checkJs src`), and the command is recorded where the project already records commands — a `scripts` entry, a `Makefile` target, the README. **A new configuration file for a checker is a `project` cost, not a `tool` cost.** Checker configuration files can outnumber a small program's own files and push a `tool` story past both the 2–3× its level promises and the 5× ceiling ([engineering-level.md](engineering-level.md)). Defaults buy the same guarantee for one line instead of one file; what they give up is that the next person's run may disagree with yours, which is precisely what a level with no other dependants can afford. Files that *are* the deliverable — the README, `.gitignore`, `.editorconfig`, the lockfile, the runtime declaration — are written at every level: they are the item, not its configuration.

**The format check covers the project's files, never `.epico/`.** `prettier --check .` also reads the story's own Markdown, and the run report written at the end of the run then fails a gate that had passed — so name the source directories and files instead of `.`. It is scope, not policy: no ignore file is written for it.

**A syntax check is not a lint.** `node --check`, `python -m py_compile` and `bash -n` prove that a file parses and nothing else; a legend line that names one of them as Lint counts the item as **omitted**, not covered, and says so on the line. Left unasked, a run accepts whatever runtime it finds — even one out of support — declares no version, and carries no formatter, linter, type checker or `.editorconfig`; tests and error handling are the only always-tier items that appear without being asked. The runtime version is chosen the way every technical decision is: a recommended version with its reason, in one line ([clarify.md](clarify.md#clarify-protocol)).

## By context

Activated by a signal in the tree or in the request. The signal is the rule; the Analyst reports which are present.

| Item | Signal | What it proves | Typical command |
|---|---|---|---|
| Integration and E2E tests | an HTTP surface, a UI, a database | the parts work together, as the user reaches them | authored by the Test Advisor; E2E by the selected tool ([preferred-tooling.md](preferred-tooling.md)) |
| Contract tests | an API with more than one consumer | producer and consumers agree on the shape | a schema check per consumer (OpenAPI, JSON Schema, Pact) |
| Structured logs and health | a process that stays running | one event per line with keys, and a health endpoint answers. No secret, token, credential or PII reaches any log line, at any level — redacted at the logger, not at each call site, where one forgotten call leaks. Levels mean something: ERROR a human must act, WARN degraded and recovered on its own, INFO a business event, DEBUG off in production; the level can be raised without a redeploy (an environment variable or a signal) | a log line parses as JSON or key=value; `curl /health` returns 200; the logger's redaction config lists the secret fields; the level variable is read at start-up |
| Versioned migrations | a database | schema changes are ordered and reversible | the migration tool's `status`, and a down migration |
| SAST | code that receives external input or handles auth | defects in the project's own code, not its dependencies | `opengrep` (or `semgrep`) with a registry ruleset |
| Image digest, non-root, scan | a `Dockerfile` | base pinned by `sha256:`, no root user, no known CVE in the image | `grep '@sha256:' Dockerfile`; a `USER` line; `trivy image` |
| Hardened workflows | `.github/workflows/` | every action pinned to a commit SHA, never a mutable tag; `permissions:` declared and least-privilege — read by default, write only on the job that needs it; no `pull_request_target` or `workflow_run` that checks out untrusted code, and no `${{ github.event.* }}` expanded inside `run:` — it goes through `env:`; `actions/checkout` with `persist-credentials: false`; a `timeout-minutes` on every job; a self-hosted runner only on a private repository, isolated and ephemeral — on a public one any fork's pull request runs code on it | `zizmor .github/workflows` · `actionlint`; a grep for `@v[0-9]`; StepSecurity Harden-Runner as each job's first step, to audit or block its egress |
| CI mirror | `.github/workflows/` | the CI jobs pass on this machine before a push, so a red is caught here and not on someone else's runner. The run mirrors the runner's **environment**, not just its command: a clean checkout, with no local build artifacts, no installed dependencies and no `.env` — a divergence there gives reds, or greens, the runner cannot reproduce. `act` runs as root, so a job asserting a refusal on an unreadable file fails under it; for those cases a plain local run as a normal user is the faithful check | `act -j <job>` per job, after `act -l` lists them |
| Pre-commit hook | a git repository, at `project` and above | the fast checks — secrets first, then format and lint — run before a commit exists, not only in CI | `.pre-commit-config.yaml` with `gitleaks`; `pre-commit run --all-files` |
| Accessibility | a frontend | the UI is usable without a mouse or a screen | an axe run on the rendered pages |
| Licence, SBOM, signing | something published or distributed | who may use it, what is in it, that it is what it claims | `LICENSE` exists; `syft`; `cosign` |
| Security policy | something published or distributed | a reporter knows where to send a vulnerability privately and what to expect | `SECURITY.md` exists and names a private channel |
| Branch protection | a remote repository | the default branch refuses deletion and force-push, and a merge waits for the CI checks. It is a setting of the forge, not a file of the tree, so the proof reads the forge | `gh api repos/{owner}/{repo}/rules/branches/{default}` lists `deletion`, `non_fast_forward` and `required_status_checks` |
| Minimum dependency age | dependencies and a CI | a version younger than seven days is not taken | Renovate `minimumReleaseAge` · Dependabot `cooldown` · `depsguard` |
| Format version | the program writes a file it reads back — a save file, a cache, a configuration | a format can be told apart from its successors, so a later version reads an older file instead of misreading it. The atomic write itself is already the floor's ([data integrity](#the-security-floor--five-items-no-level-drops)) | a version field in the format; the story's test reads a file written by the previous format |

## On request

Costly or narrow; activated only by a requirement that names them.

| Item | When | Typical command |
|---|---|---|
| Fuzzing | a parser, a protocol, a file format | `cargo fuzz` · `afl-fuzz` · `go test -fuzz` |
| Benchmarks | a stated performance requirement | `hyperfine` · `wrk` · `vegeta` · `go test -bench` |
| Coverage threshold | a team policy that names a number | the test runner's coverage flag against the number |
| Mutation testing | a suite whose strength is in question | `cargo-mutants` · `stryker` |
| Repo posture score (OpenSSF Scorecard) | a published repository whose security posture is reported to its users | `scorecard --repo=<forge>/<owner>/<repo>` — it reads the forge's settings, so it runs against the remote |
| Behavioural malware scan (Socket) | a dependency list where a zero-day package must be caught by what it does, not by a known CVE | `socket scan create` — SCA finds the known CVE, this finds the install script that phones home |
| Tracing (OpenTelemetry) | a request that crosses services or processes, whose latency or failure has to be followed end to end | the `opentelemetry` SDK of the language, the trace propagated through the request context; a span exported to a local collector |
| Build provenance (SLSA) | an artifact others install and must trust came from this commit and this pipeline | `actions/attest-build-provenance`; `gh attestation verify` — it needs the forge's OIDC identity, the one step here that cannot run locally |

## The legend line

```
- Q2: Lint — `golangci-lint run ./...` exits 0
- Q7: Dependency vulnerabilities — `osv-scanner .` reports none (tool: installed; `trivy` absent)
- Q12: Contract tests — the three frontends validate against `openapi.yaml` (request: three consumers)
```

Number in catalog order, one command per line, the reason on the line when the item is a context or on-request one. A sub-task that exercises an item cites it — `- Quality: Q2, Q7` beside `Requirements:`. The Quality Gates section of `tasks.md` then carries one box per line, `- [ ] Q2 — Lint: golangci-lint run ./... exits 0`, after the five fixed gates, and validate settles each by running its command ([validate-mode.md](validate-mode.md)). The first backtick span of a gate is the whole command validate runs, so write it complete: every argument inside the span, no `<placeholder>`, and a check over several targets or jobs as one gate line per target, sharing the legend's `Qn`, each with distinct text before the colon (`- [ ] Q5 — Unit tests (api): <command>` and `- [ ] Q5 — Unit tests (web): <command>`), so each target is closed by its own prefix and reused on its own — never a command in one span and its arguments in the next. A span validate cannot run whole is run in part and reads as the check failing. `cross-reference.sh` reports the legend's coverage: a `Qn` no sub-task cites is an orphan; a cited `Qn` the legend does not declare is a phantom.

### Gates and caches

A gate never switches a tool's own result cache off — a cached pass is the tool's own proof, and defeating it makes the gate slow and its result impossible to reuse. Name tool and flag together, never a bare flag:

- turbo: `TURBO_FORCE` or `--force`
- nx: `--skip-nx-cache`
- jest: `--no-cache`
- pytest: `--cache-clear`
- gradle: `--rerun-tasks` or `--no-build-cache`

`go test -count=1` is only for tests that read external state (a database, the network); everywhere else leave Go's test cache on. Prefer incremental modes (Stryker `incremental`) to a full re-run. No gate runs a command another gate already runs: a `make test` that already runs the unit suite does not sit beside a `make test-unit` gate — keep one. Examples stay generic; they never name a real project.

**To a layperson the legend is rendered as the checks that were run**, each named by what it checked — "I checked the code for known mistakes", "I checked the libraries for known security problems" — never by identifier ([plain-register.md](plain-register.md)).
