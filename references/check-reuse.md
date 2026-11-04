# Check Reuse — `epico-check`

The single home of the rules for running a check through `epico-check`: which runs are routed, which never are and why, the three modes, and how to read `epico-check stats`. Every routed step carries one pointer line here and nothing more.

**Why it exists.** A story re-runs the same validation commands several times: the Executor's Validation, its Refactor re-run, the end-of-run gates, the Auditor's reproductions. When nothing a check reads has changed since a PASS, the next run only repeats the answer. `epico-check run` returns that PASS without running the command; anything that changed, or any FAIL, runs for real.

## The command

```
epico-check run [--fresh] [--timeout <s>] -- <command>
```

It prints one JSON line — `mode`, `decision` (`ran` or `reused`), `would_reuse`, `result` (`PASS` or `FAIL`), `exit`, `evidence`, `secs`, `fingerprint`, `key`, `reason` — and exits 0 on PASS, 1 on FAIL, 2 on a usage error. Read `result` and `evidence` as the report would read the command's own exit code and output: a `reused` PASS is reported as such (`decision: reused`, `secs: 0`, evidence `reused: PASS recorded <time>` — the ledger keeps the verdict, not the output), never as a fresh run.

Two companions: `epico-check lookup -- <command>` is read-only and prints what `run` would decide; `epico-check profile --detect` prints a proposed profile, which init writes.

**The reuse key** is the command plus a fingerprint of the code (every tracked file and every untracked file git does not ignore, except `.epico/` and `.epic/`), the output of the profile's tool-version probes, the content of the profile's listed inputs (gitignored env or local-config files a check reads), and the profile file itself. Change any of them and the key changes.

**Only a PASS is ever reused.** A FAIL is recorded and never reused. `--fresh` always runs and replaces the stored result — use it when a result is in doubt.

## Routed callers

Each of these runs its repeatable checks as `epico-check run -- <cmd>`:

| Caller | Which runs |
|---|---|
| [executor.md](../agents/executor.md) | step 4 Validation and the step 5 Refactor re-runs |
| [run-mode.md](run-mode.md) | the inline route's validation, and the end-of-run quality gates |
| [auditor.md](../agents/auditor.md) | Part 2: reproducing a claim from an Executor report |
| [lean-route.md](lean-route.md) | the whole check |
| [validate-mode.md](validate-mode.md) | VALIDATE's command runs |

## Runs that never route

These run the command directly, never through `epico-check`, because reuse would defeat their purpose:

| Run | Why it stays direct |
|---|---|
| The Test Advisor's Red runs ([test-advisor.md](../agents/test-advisor.md)) | They must observe a FAIL at an assertion. A reused PASS cannot be a Red. |
| The deferred E2E Red run (Run mode, *Deferred Red for E2E sub-tasks*) | Same: the orchestrator must see the test fail before the Executor starts. |
| The Auditor's bugfix guard on the base commit (check 11, *The guard must bite*) | It must observe a FAIL on the old code. The base commit is not the working tree either. |
| The final reviewer's clean-copy run ([final-reviewer.md](../agents/final-reviewer.md)) | It runs outside the working tree, on a clean copy: the fingerprint of the working tree says nothing about it. |

The rule behind the table: a run that must **observe a failure**, or that runs **outside the working tree**, is not a repeat of a check — so it is not routed. When a new caller appears, apply the same question.

## Modes

The mode is `mode` in `.epico/reuse-profile.json`; a missing profile means `shadow`. The file is `{"version":1,"mode":"off|shadow|on","tools":[...],"inputs":[...],"never":[...]}`, written by init and edited by hand. To switch, change `mode` in the profile.

| Mode | What happens |
|---|---|
| `shadow` | The default, measure only. Every check runs; the log records whether a PASS would have been reused. |
| `on` | A PASS for the same key is returned without running. Set by hand, once `epico-check stats` shows no disagreement traced to the key. |
| `off` | The check runs and nothing is recorded. |

`tools` lists commands whose version output joins the key; `inputs` lists gitignored files whose content joins it; `never` lists literal substrings — a command holding one always runs and records nothing (use it for checks that read state outside the repository).

The ledger lives in the git common directory (`epico/reuse/ledger.json`), shared by every worktree of the repository, and is never committed. Only `epico-check run` writes it; a hook denies an agent's direct write.

## Reading `epico-check stats`

`epico-check stats` summarises the shadow log: `runs`, `would_reuse`, `agreed`, `disagreed` (each `{command, at}`) and `secs_reusable` — the time reuse would have saved.

**A disagreement is not a false green.** It is a check that would have been reused as a PASS but failed when it actually ran. Read it as one of two things:

- **a flaky check** — it fails and passes with the same code; fix or quarantine the check;
- **a check that depends on state outside the key** — a service, the clock, the network, a file the profile does not list. Add the command to `never`, or list the file in `inputs`.

Go to `on` only when `stats` shows no disagreement traced to the key itself, and `secs_reusable` is worth the switch.

## Secrets

The ledger stores command strings under the git directory. A gate or validation command must therefore never embed a secret — no token, password or key in the command line. Pass it through the environment, or a file listed in `inputs`, and have the command read it from there.
