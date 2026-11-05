#!/usr/bin/env bash
# Decides whether a check (a command that proves something about the code) has
# to run again, or whether its last PASS on the very same code still stands.
#
# Usage: bash scripts/check-reuse.sh run [--fresh] [--timeout <s>] -- <command>
#        bash scripts/check-reuse.sh lookup -- <command>
#        bash scripts/check-reuse.sh stats
#        bash scripts/check-reuse.sh profile --detect
#
# Exit 0 = done (for `run`: the command passed)
# Exit 1 = refused / (for `run`: the command failed)
# Exit 2 = invalid input (missing or malformed arguments, unknown subcommand)
#
# Output: ONE JSON object on stdout on every path that reaches a verdict, so a
# consumer can pipe stdout straight into jq; every human-readable diagnostic
# goes to stderr. Usage errors (exit 2) print no JSON at all — nothing has been
# looked at yet, so there is nothing to report on (the convention
# close-subtask.sh, validate-story.sh and archive-story.sh already share).
#
# `run [--fresh] [--timeout <s>] -- <command>` runs the command from the
# repository's top level (the current directory outside a git work tree) in its
# own session, under `timeout` (default 300 s), and reports ONE JSON line. The
# command's own output never reaches stdout:
#   mode         "shadow" | "on" | "off"
#   decision     "ran" | "reused"
#   would_reuse  boolean
#   result       "PASS" | "FAIL"        PASS only for exit code 0
#   exit         the command's exit code (124 when it ran out of time)
#   evidence     the last non-empty output line, cargo totals summed, or
#                "timed out after <s>s"; at most 200 characters
#   secs         whole seconds the command took
#   fingerprint  string | null          as for `lookup`
#   key          string | null          as for `lookup`
#   reason       string                 why no reuse was possible; "" when none
# Exit 0 on PASS, 1 on FAIL, 2 on a usage error (no JSON, nothing run).
#
# THE DECISION (the profile's `mode`; shadow when there is no profile):
#   off      runs, records nothing.
#   shadow   runs every check, records its result, and appends one line to the
#            shadow log saying whether the ledger already held a PASS for the key
#            (`would_reuse`). Nothing is ever skipped.
#   on       a PASS recorded for the same key is returned as decision "reused",
#            without running the command.
# In every mode a command is run, and nothing is recorded for it, when it holds an
# entry of the profile's `never` list (a literal substring), when there is no
# fingerprint, or when there is no key. `--fresh` always runs and replaces the
# recorded result. Only a PASS is ever a hit; a FAIL is recorded, never reused.
#
# THE LEDGER is <git-common-dir>/epico/reuse/ledger.json, shared by every
# worktree of the repository and never committed:
#   {"version": 1, "entries": {<key>: {command, result, fingerprint, at, secs}}}
# capped at 2000 entries (the oldest `at` goes first). The shadow log beside it is
# JSON lines {at, command, key, would_reuse, result, secs}, capped at 5000. Both
# are written through a temp file and a rename. A ledger that is not valid JSON,
# has the wrong shape or another version is renamed to
# ledger.json.unreadable-<UTC stamp> (never replacing an earlier copy) and the
# run goes on as if nothing were recorded. A failure to record or to set aside
# warns on stderr and changes neither the verdict nor the exit code. A non-PASS
# that is not recorded — the ledger lock given up on, or the write under it
# failed — leaves void.<key> beside the ledger: that key is no hit until its next
# recorded run, so its older PASS is never reused, and the reason says so. A void
# whose key the ledger no longer holds is removed by the next recorded run.
#
# `profile --detect` prints a proposed profile and writes nothing: one version
# probe per toolchain whose manifest is in the project's top level AND whose binary
# is on PATH, and as `inputs` the gitignored .env, .env.*, .dev.vars and
# *.local.{json,yaml,yml,toml,php} files outside node_modules/ and vendor/. `never`
# is left empty: which commands need credentials, docker or a live service is a
# judgement made at init. A manifest it cannot parse, or a directory that is not a
# git work tree, loses only what depends on it, with a warning on stderr and exit 0.
#
# `stats` summarises the shadow log: {runs, would_reuse, agreed, disagreed,
# secs_reusable}. A disagreement is a run that would have been reused as a PASS
# and failed when it ran: {command, at}.
#
# `lookup -- <command>` runs nothing and reports what `run` would decide:
#   mode         "shadow" | "on" | "off" — the project's reuse mode (shadow until
#                the profile is read)
#   would_reuse  boolean
#   fingerprint  string | null — the code fingerprint; null when it cannot be
#                computed, and then `reason` says why
#   key          string | null — the reuse key; null when it cannot be built, and
#                then `reason` says why
#   last         object | null — the ledger entry for the key (null until the
#                ledger is read)
#   reason       string | null — why no reuse is possible, when it is not;
#                several causes are joined with "; "
#
# THE PROFILE is .epico/reuse-profile.json at the repository's top level:
#   {"version": 1, "mode": "off|shadow|on", "tools": [...], "inputs": [...],
#    "never": [...]}
# Absent, it yields the shadow defaults with reason "profile absent". Invalid
# JSON, a version other than 1 or a wrong shape yield the same defaults plus a
# warning on stderr. The file is only ever read, never written here.
#
# THE REUSE KEY is the git hash of a canonical JSON document holding the
# command, the code fingerprint, the output of every probe in `tools` (stdout and
# stderr, whatever the exit code, as its blob hash; null when the probe's binary
# is not on PATH), the blob hash of every file in `inputs` (null when it does not
# exist) and the blob hash of the profile file itself. Probes run from the top
# level. A probe that runs past EPICO_REUSE_PROBE_TIMEOUT seconds (default 10), an
# input that is not a regular file or cannot be read, a profile file that cannot
# be hashed, and a missing `timeout` leave NO key (null, with a reason): a stable
# placeholder would hide a real change.
#
# THE CODE FINGERPRINT names the code a check ran on: every tracked file and
# every untracked file git does not ignore, minus the .epico/ and .epic/
# directories — whichever way those are kept (versioned, gitignored, or
# gitignored while holding a tracked file). It is a git tree id, computed on a
# COPY of the real index, so the real index is never touched:
#   1. copy the real index (`git rev-parse --git-path index`, worktree-aware)
#      into a temp file, modification time included (`cp -p`) — the copy keeps
#      git's stat cache and its protection against racily clean entries, an empty
#      temp index would re-hash the whole tree;
#   2. `git add -A -- .` on the copy;
#   3. `git rm -r -q --cached --ignore-unmatch -- .epico .epic` on the copy;
#   4. `git write-tree` on the copy.
# TWO FORMS ARE DELIBERATELY AVOIDED, and neither is an oversight to restore:
#   - an `:(exclude).epico` pathspec on `git add` — it exits 1 ("paths are
#     ignored") when .epico/ is gitignored;
#   - branching on `git check-ignore` — it reports an ignored directory that
#     holds a tracked file as not ignored.
# No fingerprint (null, with a reason) when: the directory is not a git work
# tree; any of the git steps fails (an unreadable file makes `add` fail); or a
# submodule or nested repository holds uncommitted content, because `git add -A`
# records its commit, not its dirty content.

set -euo pipefail

USAGE='Usage: check-reuse.sh run [--fresh] [--timeout <s>] -- <command> | lookup -- <command> | stats | profile --detect'

usage_error() {
  printf '%s\n' "$1" >&2
  printf '%s\n' "$USAGE" >&2
  exit 2
}

IDX=""         # the temporary copy of the index
LEDGER_TMP=""  # the ledger being written, before its rename
SHADOW_TMP=""  # the shadow log being trimmed, before its rename
PROBE_TMP=""   # the file a probe's output is captured in
RUN_LOG=""     # the file the checked command's output is captured in
RUN_SID=""     # the file the command's session leader writes its pid to
LOCK_DIR=""    # the ledger lock this run holds
LOCK_TOKEN=""  # the owner token this run wrote in it
BREAK_FILE=""  # ledger.lock.break while this run is breaking a stale lock
BREAK_TOKEN="" # the token this run wrote in it
cleanup() {
  # A signal to the runner must not leave the checked command running in its own
  # session until its timeout.
  if [ -n "$RUN_SID" ] && [ -s "$RUN_SID" ]; then
    kill -TERM -- "-$(cat -- "$RUN_SID" 2>/dev/null)" 2>/dev/null || true
  fi
  # LOCK_DIR is set only by ledger_lock, so ledger_unlock is defined by then; it
  # releases only while the lock is still ours.
  if [ -n "$LOCK_DIR" ]; then ledger_unlock; fi
  # BREAK_FILE is set only by ledger_break, so ledger_break_drop is defined by then.
  if [ -n "$BREAK_FILE" ]; then ledger_break_drop "$BREAK_FILE" "$BREAK_TOKEN"; fi
  if [ -n "$IDX" ]; then rm -f -- "$IDX"; fi
  if [ -n "$PROBE_TMP" ]; then rm -f -- "$PROBE_TMP"; fi
  if [ -n "$RUN_LOG" ]; then rm -f -- "$RUN_LOG"; fi
  if [ -n "$RUN_SID" ]; then rm -f -- "$RUN_SID"; fi
  if [ -n "$LEDGER_TMP" ]; then rm -f -- "$LEDGER_TMP"; fi
  if [ -n "$SHADOW_TMP" ]; then rm -f -- "$SHADOW_TMP"; fi
}
trap cleanup EXIT

FP=""          # the fingerprint, empty when none could be computed
FP_REASON=""   # why FP is empty
TOP=""         # the work tree's top level, empty outside a git work tree

# fingerprint — sets FP, or FP_REASON when no fingerprint can be computed.
fingerprint() {
  local top gitidx out path status_out

  FP=""
  FP_REASON=""
  TOP=""

  if ! top=$(git rev-parse --show-toplevel 2>/dev/null) || [ -z "$top" ]; then
    FP_REASON="not a git work tree"
    return 0
  fi
  TOP="$top"

  if ! gitidx=$(git -C "$top" rev-parse --git-path index 2>/dev/null) || [ -z "$gitidx" ]; then
    FP_REASON="git could not locate its index"
    return 0
  fi
  case "$gitidx" in
    /*) ;;
    *) gitidx="$top/$gitidx" ;;
  esac

  # The copy goes beside the real index, inside the git directory: a TMPDIR that
  # sits inside the work tree would put the copy into the very tree being
  # fingerprinted and move the fingerprint on every call. A git directory that
  # cannot be written to falls back to the temporary directory.
  if ! IDX=$(mktemp "${gitidx%/*}/epico-fp.XXXXXX" 2>/dev/null) &&
    ! IDX=$(mktemp "${TMPDIR:-/tmp}/epico-reuse.XXXXXX" 2>/dev/null); then
    IDX=""
    FP_REASON="no temporary file could be created"
    return 0
  fi
  if [ -f "$gitidx" ]; then
    # -p keeps the real index's mtime. Git decides whether a recorded stat can be
    # trusted by comparing each entry's mtime with the index file's own mtime
    # ("racily clean"); a copy with a fresh mtime switches that off, and a
    # same-size edit made in the second the index was written goes unseen.
    if ! cp -p -- "$gitidx" "$IDX"; then
      FP_REASON="the git index could not be copied"
      return 0
    fi
  else
    # No index yet (a repository with nothing staged): git starts from none.
    rm -f -- "$IDX"
  fi

  if ! out=$(GIT_INDEX_FILE="$IDX" git -C "$top" add -A -- . 2>&1); then
    FP_REASON="git add failed: $(first_line "$out")"
    return 0
  fi
  # `add -A` records a submodule's, or a nested repository's, commit and never
  # its uncommitted content, so each checked-out one is asked for it directly.
  if ! out=$(GIT_INDEX_FILE="$IDX" git -C "$top" ls-files -s | awk -F'\t' '$1 ~ /^160000 / { print $2 }'); then
    FP_REASON="git ls-files failed"
    return 0
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      \"*)
        FP_REASON="a nested repository path git quotes cannot be checked: $path"
        return 0
        ;;
    esac
    [ -e "$top/$path/.git" ] || continue
    if ! status_out=$(git -C "$top/$path" --no-optional-locks status --porcelain --ignore-submodules=none 2>&1); then
      FP_REASON="git status failed in $path: $(first_line "$status_out")"
      return 0
    fi
    if [ -n "$status_out" ]; then
      FP_REASON="a submodule or nested repository holds uncommitted changes: $path"
      return 0
    fi
  done <<<"$out"
  if ! out=$(GIT_INDEX_FILE="$IDX" git -C "$top" rm -r -q --cached --ignore-unmatch -- .epico .epic 2>&1); then
    FP_REASON="git rm failed: $(first_line "$out")"
    return 0
  fi
  if ! out=$(GIT_INDEX_FILE="$IDX" git -C "$top" write-tree 2>&1); then
    FP_REASON="git write-tree failed: $(first_line "$out")"
    return 0
  fi
  FP="$out"
}

# first_line <text> — the first line, with no pipe: under pipefail a long text
# makes `printf | head` die of SIGPIPE and abort the script.
first_line() {
  printf '%s\n' "${1%%$'\n'*}"
}

warn() {
  printf 'check-reuse.sh: warning: %s\n' "$1" >&2
}

DEFAULT_PROFILE='{"version":1,"mode":"shadow","tools":[],"inputs":[],"never":[]}'
PROFILE_JSON="$DEFAULT_PROFILE"   # the profile in force
PROFILE_FILE=""                   # where it is read from
PROFILE_REASON=""                 # set when the defaults are in force

# load_profile — sets PROFILE_JSON, PROFILE_FILE and PROFILE_REASON. Never
# writes: a profile that cannot be used is left exactly as it is.
load_profile() {
  local raw

  PROFILE_JSON="$DEFAULT_PROFILE"
  PROFILE_REASON=""
  PROFILE_FILE="${TOP:-$PWD}/.epico/reuse-profile.json"

  if [ ! -e "$PROFILE_FILE" ]; then
    PROFILE_REASON="profile absent"
    return 0
  fi
  if ! raw=$(cat -- "$PROFILE_FILE" 2>/dev/null); then
    warn "the reuse profile cannot be read; using the shadow defaults"
    PROFILE_REASON="profile unreadable"
    return 0
  fi
  # Slurped, so a file holding several JSON documents is one invalid profile and
  # never a first document that says `on` followed by a valid second one. A tool
  # or input holding a newline would be split into two entries on the way out.
  if ! jq -e -s '
        length == 1 and (.[0] |
          type == "object" and .version == 1
          and (.mode | IN("off", "shadow", "on"))
          and (.tools | type == "array" and all(type == "string" and (contains("\n") | not)))
          and (.inputs | type == "array" and all(type == "string" and (contains("\n") | not)))
          and (.never | type == "array" and all(type == "string")))
      ' <<<"$raw" >/dev/null 2>&1; then
    warn "the reuse profile is not valid for format version 1; using the shadow defaults"
    PROFILE_REASON="profile invalid"
    return 0
  fi
  PROFILE_JSON=$(jq -c '.' <<<"$raw")
}

PROBE_OUT=""   # the git blob hash of the last probe's output

# run_probe <probe> — runs the probe from the top level and puts the blob hash of
# its stdout and stderr into PROBE_OUT, whatever its exit code (`java -version`
# prints to stderr and some tools exit non-zero). The output enters the key as a
# hash, so a probe that prints a megabyte never meets the argument-size limit.
# Output goes to a file, not a pipe, so a grandchild holding the pipe open cannot
# outlive the timeout. Returns 124 when the probe ran out of time, 3 when there
# is no `timeout` to bound it with, 1 when it could not be run or read at all.
run_probe() {
  local probe="$1" limit="${EPICO_REUSE_PROBE_TIMEOUT:-10}" status=0

  case "$limit" in '' | *[!0-9]*) limit=10 ;; esac
  [ "$limit" -gt 0 ] || limit=10
  command -v timeout >/dev/null 2>&1 || return 3
  PROBE_OUT=""
  PROBE_TMP=$(mktemp "${TMPDIR:-/tmp}/epico-reuse.XXXXXX") || {
    PROBE_TMP=""
    return 1
  }
  (cd "$TOP" && timeout -k 2 "$limit" bash -c "$probe" </dev/null >"$PROBE_TMP" 2>&1) || status=$?
  case "$status" in 124 | 137) status=124 ;; *) status=0 ;; esac
  if [ "$status" -eq 0 ]; then
    PROBE_OUT=$(git -C "$TOP" hash-object --no-filters -- "$PROBE_TMP" 2>/dev/null) || status=1
  fi
  rm -f -- "$PROBE_TMP"
  PROBE_TMP=""
  return "$status"
}

KEY=""          # the reuse key, empty when none could be built
KEY_REASON=""   # why KEY is empty

# build_key <command> — sets KEY, or KEY_REASON when no key can be built. Needs
# FP, TOP and a loaded profile. A fingerprint that is missing leaves the key
# empty without a reason of its own: FP_REASON already says why.
build_key() {
  local command_string="$1" probe first path abs blob phash status absent
  local tools="" inputs="" profile_blob="null"

  KEY=""
  KEY_REASON=""
  [ -n "$FP" ] || return 0

  # The cheap reads come first, so an unreadable input never waits on a probe.
  while IFS= read -r path; do
    abs="$TOP/$path"
    if [ ! -e "$abs" ]; then
      blob=""
    elif [ -d "$abs" ]; then
      KEY_REASON="profile input is a directory: $path"
      return 0
    elif [ ! -f "$abs" ]; then
      # A FIFO or a device would block `git hash-object` for good.
      KEY_REASON="profile input is not a regular file: $path"
      return 0
    elif ! blob=$(git -C "$TOP" hash-object --no-filters -- "$abs" 2>/dev/null); then
      KEY_REASON="profile input cannot be read: $path"
      return 0
    fi
    inputs+=$(jq -nc --arg path "$path" --arg blob "$blob" \
      '{path: $path, blob: (if $blob == "" then null else $blob end)}')$'\n'
  done < <(jq -r '.inputs[]' <<<"$PROFILE_JSON")

  if [ -e "$PROFILE_FILE" ]; then
    if ! phash=$(git -C "$TOP" hash-object --no-filters -- "$PROFILE_FILE" 2>/dev/null); then
      KEY_REASON="the reuse profile cannot be hashed"
      return 0
    fi
    profile_blob=$(jq -nc --arg h "$phash" '$h')
  fi

  while IFS= read -r probe; do
    read -r first _ <<<"$probe"
    # A binary that is not on PATH is "absent". Only a plain word is looked up:
    # `VAR=1 tool --version` or a quoted first word is shell syntax, and calling
    # it "absent" would freeze the key whatever the tool printed — bash runs it.
    # The lookup is made from the top level, where the probe itself runs.
    absent=0
    case "$first" in
      '') absent=1 ;;
      *[!A-Za-z0-9_+./-]*) ;;
      *) (cd "$TOP" && command -v -- "$first" >/dev/null 2>&1) || absent=1 ;;
    esac
    if [ "$absent" -eq 1 ]; then
      tools+=$(jq -nc --arg probe "$probe" '{probe: $probe, output: null}')$'\n'
      continue
    fi
    status=0
    run_probe "$probe" || status=$?
    case "$status" in
      0) ;;
      124)
        KEY_REASON="probe timed out: $probe"
        return 0
        ;;
      3)
        KEY_REASON="timeout is not installed, so probes cannot be bounded: $probe"
        return 0
        ;;
      *)
        KEY_REASON="probe could not run: $probe"
        return 0
        ;;
    esac
    tools+=$(jq -nc --arg probe "$probe" --arg output "$PROBE_OUT" \
      '{probe: $probe, output: $output}')$'\n'
  done < <(jq -r '.tools[]' <<<"$PROFILE_JSON")

  if ! KEY=$(jq -ncS \
    --arg command "$command_string" \
    --arg tree "$FP" \
    --argjson tools "$(printf '%s' "$tools" | jq -sc .)" \
    --argjson inputs "$(printf '%s' "$inputs" | jq -sc .)" \
    --argjson profile "$profile_blob" \
    '{command: $command, tree: $tree, tools: $tools, inputs: $inputs, profile: $profile}' |
    git -C "$TOP" hash-object --stdin 2>/dev/null); then
    KEY=""
    KEY_REASON="the reuse key could not be computed"
  fi
}

# join_reasons — every non-empty reason, joined with "; ".
join_reasons() {
  local out="" r
  for r in "$@"; do
    if [ -n "$r" ]; then
      if [ -n "$out" ]; then out+="; "; fi
      out+="$r"
    fi
  done
  printf '%s' "$out"
}

# cargo prints one "test result:" per test binary and ends on the doc-test one,
# often "0 passed" — so the last line alone reads as if nothing ran. With more
# than one summary, they are added up; any other output keeps its last line.
runner_totals() {
  local out
  out="$(cat)"
  printf '%s' "$out" | grep -oE 'test result: [a-z]+\. [0-9]+ passed; [0-9]+ failed' |
    awk '{ p += $4; f += $6; n++ } END { if (n > 1) printf "cargo test: %d passed, %d failed in %d binaries", p, f, n }' |
    grep . || printf '%s' "$out" | awk 'NF' | tail -1
}

RUN_EXIT=0
RUN_EVIDENCE=""
RUN_STARTED=1   # 0 when the command could not be started at all

# run_command <command> <timeout> — runs the command and sets RUN_EXIT and
# RUN_EVIDENCE. Output goes to a file, not a pipe, and the command runs in its
# own session: a `cargo run &` inside a gate once kept a captured pipe open until
# the timeout (300 s lost in a rust run). The session is killed once the command
# returns, so a server it started never outlives its check.
run_command() {
  local command_string="$1" limit="$2" code=0 dir

  dir="${TOP:-$PWD}"
  RUN_STARTED=1
  # Where the command cannot be started, the verdict is FAIL but it is not a
  # result: nothing is recorded for it, so it can never replace a real PASS.
  if ! command -v setsid >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
    RUN_STARTED=0
    RUN_EXIT=126
    RUN_EVIDENCE="setsid and timeout are needed to run a check"
    return 0
  fi
  if ! RUN_LOG=$(mktemp "${TMPDIR:-/tmp}/epico-reuse.XXXXXX" 2>/dev/null); then
    RUN_LOG=""
    RUN_STARTED=0
    RUN_EXIT=126
    RUN_EVIDENCE="no temporary file could be created"
    return 0
  fi
  if ! RUN_SID=$(mktemp "${TMPDIR:-/tmp}/epico-reuse.XXXXXX" 2>/dev/null); then
    RUN_SID=""
    RUN_STARTED=0
    RUN_EXIT=126
    RUN_EVIDENCE="no temporary file could be created"
    return 0
  fi
  # --fork makes setsid succeed even where this shell's job is a group leader;
  # the new session's leader writes its own pid, which names the group to kill.
  # shellcheck disable=SC2016  # $$ and $0 belong to the inner bash
  (cd "$dir" && setsid --fork --wait bash -c 'echo "$$" > "$0"; exec timeout "$1" bash -c "$2"' "$RUN_SID" "$limit" "$command_string") </dev/null >"$RUN_LOG" 2>&1 || code=$?
  if [ -s "$RUN_SID" ]; then kill -TERM -- "-$(cat "$RUN_SID")" 2>/dev/null || true; fi
  if [ "$code" -eq 124 ]; then
    RUN_EVIDENCE="timed out after ${limit}s"
  else
    RUN_EVIDENCE=$(tr -d '\r' <"$RUN_LOG" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | runner_totals | cut -c1-200)
  fi
  RUN_EXIT="$code"
  rm -f -- "$RUN_LOG" "$RUN_SID"
  RUN_LOG=""
  RUN_SID=""
}

LEDGER_DIR=""         # <git-common-dir>/epico/reuse; empty when git cannot name it
LEDGER_FILE=""
LEDGER_NOTE=""        # why there is no ledger directory
LEDGER_JSON=""        # the ledger in force: a valid version-1 ledger, possibly empty
LEDGER_BLOCKED=0      # 1 when an unreadable ledger could not be set aside
LEDGER_RECORDED=0     # 1 once ledger_write has renamed the new ledger into place
EMPTY_LEDGER='{"version":1,"entries":{}}'
LEDGER_CAP=2000
SHADOW_CAP=5000

# resolve_ledger_dir — the ledger lives in the git COMMON dir, so every worktree
# of one repository shares it. Plain --git-common-dir is relative in the main
# worktree (`.git`), hence the absolute form (git 2.31 or newer).
resolve_ledger_dir() {
  local common

  LEDGER_DIR=""
  LEDGER_FILE=""
  LEDGER_NOTE=""
  if ! common=$(git -C "${TOP:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || [ -z "$common" ]; then
    LEDGER_NOTE="git cannot name its common directory (git 2.31 or newer is needed)"
    return 0
  fi
  LEDGER_DIR="$common/epico/reuse"
  LEDGER_FILE="$LEDGER_DIR/ledger.json"
}

# ledger_read <set-aside> — sets LEDGER_JSON to the ledger, or to an empty one
# when there is none or it is unreadable (invalid JSON, a wrong shape, a version
# other than 1). With <set-aside> = 1 an unreadable ledger is renamed to
# ledger.json.unreadable-<UTC stamp>, a name that never replaces an earlier
# copy; when that fails the ledger is left untouched and LEDGER_BLOCKED is 1, so
# nothing is written over it.
ledger_read() {
  local mutate="$1" raw stamp aside n

  LEDGER_JSON="$EMPTY_LEDGER"
  LEDGER_BLOCKED=0
  if [ ! -e "$LEDGER_FILE" ] && [ ! -L "$LEDGER_FILE" ]; then return 0; fi
  if raw=$(cat -- "$LEDGER_FILE" 2>/dev/null) && jq -e -s '
        length == 1 and (.[0] |
          type == "object" and .version == 1 and (.entries | type == "object")
          and (.entries | all(.[]; type == "object"
            and (.result | type == "string") and (.at | type == "string"))))
      ' <<<"$raw" >/dev/null 2>&1; then
    LEDGER_JSON=$(jq -c '.' <<<"$raw")
    return 0
  fi
  [ "$mutate" = 1 ] || return 0

  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  aside="$LEDGER_FILE.unreadable-$stamp"
  n=0
  while [ -e "$aside" ] || [ -L "$aside" ]; do
    n=$((n + 1))
    aside="$LEDGER_FILE.unreadable-$stamp-$n"
  done
  if mv -- "$LEDGER_FILE" "$aside" 2>/dev/null; then
    warn "the reuse ledger was unreadable; it was set aside as ${aside##*/}"
  else
    LEDGER_BLOCKED=1
    warn "the reuse ledger is unreadable and could not be set aside; checks run as if nothing were recorded"
  fi
}


# ledger_lock — serialises the read-modify-write of the ledger between runs that
# share it (parallel Executors in worktrees do). Without it, a slow run could
# write back the ledger it read before a newer FAIL was recorded, and a stale PASS
# would be reused in mode `on`. No flock: it is absent on macOS. The lock is taken
# by creating ledger.lock/owner, not by the `mkdir` of its directory — uutils'
# `mkdir` lets racing callers all succeed — and the wait, about 5 s, counts one
# holder: it restarts whenever the owner changes, so a queue of writers handing
# the lock on never makes a newer FAIL give up. A lock older than a minute
# belonged to a run that was killed, and is broken, by one run at a time
# (ledger_break); one that cannot be broken ends the wait, since waiting on it
# again would never end. Returns 1 when the lock cannot be taken.
ledger_lock() {
  local lock="$LEDGER_DIR/ledger.lock" tries=0 absent=0 owner seen="" token rc crc

  while :; do
    if mkdir -- "$lock" 2>/dev/null; then
      # The claim: noclobber makes bash open the owner file O_EXCL, so one run
      # creates it on any coreutils. The token only has to differ from the
      # previous holder's. A run that loses leaves the winner's directory —
      # rmdir refuses one holding an owner — and waits like any waiter.
      token="$$ $RANDOM"
      # Set before the claim, so a signal during it still releases an owner file
      # that is ours: ledger_unlock compares it with the token, never another's.
      LOCK_DIR="$lock"
      LOCK_TOKEN="$token"
      crc=0
      ledger_claim_file "$lock/owner" "$token" || crc=$?
      if [ "$crc" -eq 0 ]; then return 0; fi
      LOCK_DIR=""
      LOCK_TOKEN=""
      rmdir -- "$lock" 2>/dev/null || true
      # Created but not written — a full filesystem: no lock can be had here.
      if [ "$crc" -eq 2 ]; then return 1; fi
    fi
    if [ -d "$lock" ]; then
      absent=0
      owner=$(cat -- "$lock/owner" 2>/dev/null || true)
      if [ "$owner" != "$seen" ]; then
        seen=$owner
        tries=0
      fi
      tries=$((tries + 1))
      if [ "$tries" -ge 50 ]; then
        if [ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
          # Not stale. A lock another run broke since the last read — gone, or
          # taken by a new owner — is waited on afresh. Only one owner, or none,
          # on the same directory for the whole budget means giving up.
          owner=$(cat -- "$lock/owner" 2>/dev/null || true)
          # An ownerless directory may be a claim in progress — a breaker's
          # fresh lock between its mkdir and its owner file: look once more.
          if [ -z "$owner" ] && [ -d "$lock" ]; then
            sleep 0.1
            owner=$(cat -- "$lock/owner" 2>/dev/null || true)
          fi
          if [ ! -d "$lock" ] || [ "$owner" != "$seen" ]; then
            seen=$owner
            tries=0
            continue
          fi
          return 1
        fi
        rc=0
        ledger_break "$lock" "$seen" || rc=$?
        # 0 broken, 2 not ours to break now: either way, wait afresh.
        if [ "$rc" -eq 1 ]; then return 1; fi
        tries=0
        continue
      fi
    else
      # The holder may have released it between our mkdir and this test, so a
      # missing lock is retried; only a few misses in a row mean the directory
      # itself cannot be written to.
      absent=$((absent + 1))
      [ "$absent" -lt 5 ] || return 1
    fi
    sleep 0.1
  done
}

# ledger_break <lock> <owner judged dead> — breaks a stale lock, one breaker at a
# time. "Is it stale?" then "move it aside" are two steps, and two waiters that
# both judged it stale would race: the second could move aside the fresh lock the
# first just took. So the breaker first creates ledger.lock.break O_EXCL; with it
# held nobody else moves the lock, and a lock holding an owner cannot be claimed,
# so a lock still stale and still owned by the token judged dead is the dead
# run's. A break file older than a minute belonged to a breaker that was killed;
# since removing it races a fresh one, every removal of a break file checks the
# token first, and a moved lock is checked to be the dead one. Returns 0 when
# broken, 2 when it is not this run's to break now (another breaker, a new owner,
# a lock already gone), 1 when it cannot be broken (the directory cannot be
# written).
ledger_break() {
  local lock="$1" dead="$2" brk="$1.break" owner rc token moved held crc

  token="$$ $RANDOM"
  # Set before the claim: cleanup removes the break file only while it holds
  # this token, so a signal right after the create still cleans up.
  BREAK_FILE="$brk"
  BREAK_TOKEN="$token"
  crc=0
  ledger_claim_file "$brk" "$token" || crc=$?
  if [ "$crc" -ne 0 ]; then
    rc=2
    if [ "$crc" -eq 2 ] || [ ! -w "${brk%/*}" ]; then
      rc=1 # a full filesystem, or a directory that cannot be written: no break is possible
    else
      # Another breaker's file — or a killed breaker's, once it is older than a
      # minute. Its content is read before its age, and it is removed only while
      # it still holds that content (empty too: a breaker killed between its
      # create and its write), so a fresh file that replaced it stays.
      held=$(cat -- "$brk" 2>/dev/null || true)
      if [ -n "$(find "$brk" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        if [ "$(cat -- "$brk" 2>/dev/null || true)" = "$held" ]; then rm -f -- "$brk" 2>/dev/null || true; fi
        crc=0
        ledger_claim_file "$brk" "$token" || crc=$?
        if [ "$crc" -eq 2 ]; then
          rc=1 # created but not written: a full filesystem
        elif [ "$crc" -ne 0 ] && [ -n "$(find "$brk" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
          rc=1 # still there and still stale (not a file we can remove): no break is possible
        fi
      fi
    fi
    if ! [ "$(cat -- "$brk" 2>/dev/null || true)" = "$token" ]; then
      BREAK_FILE=""
      BREAK_TOKEN=""
      return "$rc"
    fi
  fi
  owner=$(cat -- "$lock/owner" 2>/dev/null || true)
  if [ "$owner" != "$dead" ] || [ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rc=2
  elif mv -- "$lock" "$lock.stale.$$" 2>/dev/null; then
    moved=$(cat -- "$lock.stale.$$/owner" 2>/dev/null || true)
    if [ "$moved" = "$dead" ]; then
      rm -rf -- "$lock.stale.$$"
      rc=0
    else
      # A live lock was moved after the check: put it back while its place is
      # free, or say that results recorded under it may be lost.
      if [ -e "$lock" ] || ! mv -- "$lock.stale.$$" "$lock" 2>/dev/null; then
        rm -rf -- "$lock.stale.$$"
        warn "a live ledger lock was moved aside while breaking a stale one; a result recorded under it may be lost"
      fi
      rc=2
    fi
  elif [ -d "$lock" ] && [ "$(cat -- "$lock/owner" 2>/dev/null || true)" = "$dead" ] &&
    [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rc=1 # still the dead lock, and it cannot be moved: the directory is not writable
  else
    rc=2
  fi
  ledger_break_drop "$brk" "$token"
  BREAK_FILE=""
  BREAK_TOKEN=""
  return "$rc"
}

# ledger_claim_file <file> <token> — a claim in two steps: an O_EXCL create
# (bash's noclobber), then the write of <token>. Returns 0 when claimed; 1 when
# not created (it exists — another run's claim — or the directory refuses it);
# 2 when created but not written (a full filesystem): the empty file is this
# run's own, so it is removed again, never left to be read as another's claim.
ledger_claim_file() {
  (
    set -o noclobber
    exec 3>"$1" || exit 1
    if ! printf '%s\n' "$2" >&3; then
      exec 3>&-
      rm -f -- "$1"
      exit 2
    fi
  ) 2>/dev/null
}

# ledger_break_drop <break file> <token> — removes it only while it holds <token>.
ledger_break_drop() {
  if [ -n "$2" ] && [ "$(cat -- "$1" 2>/dev/null || true)" = "$2" ]; then
    rm -f -- "$1" 2>/dev/null || true
  fi
}

# ledger_unlock — releases the lock only while its owner token is still this
# run's: a run whose lock was broken as stale, and taken by another holder,
# leaves that holder's lock alone. `cleanup` releases through it on a signal.
ledger_unlock() {
  local owner
  if [ -n "$LOCK_DIR" ]; then
    owner=$(cat -- "$LOCK_DIR/owner" 2>/dev/null || true)
    if [ "$owner" = "$LOCK_TOKEN" ]; then
      rm -f -- "$LOCK_DIR/owner" 2>/dev/null || true
      rmdir -- "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
  LOCK_DIR=""
  LOCK_TOKEN=""
}

# ledger_void <result> — a non-PASS that was not recorded must not leave an older
# PASS for KEY reusable: void.<key> beside the ledger makes `prepare` report no
# hit until the next locked write for KEY clears it. One empty file, written with
# or without the lock, since the lock may be exactly what could not be had.
# `true`, not `:`: a failed redirection on a special builtin ends a POSIX-mode
# shell.
ledger_void() {
  if [ "$1" = PASS ]; then return 0; fi
  if ! true 2>/dev/null >"$LEDGER_DIR/void.$KEY"; then
    warn "the key could not be voided either: an earlier PASS for this command may still be reused; run it with --fresh"
  fi
}

# ledger_record <result> <secs> <command> — records the run under KEY. The file is
# written beside the ledger and renamed into place, so it is never torn. Every
# failure warns and returns 0: the check's verdict and exit code are decided.
ledger_record() {
  if ! mkdir -p -- "$LEDGER_DIR" 2>/dev/null; then
    warn "the result was not recorded: $LEDGER_DIR cannot be created"
    return 0
  fi
  if ! ledger_lock; then
    warn "the result was not recorded: $LEDGER_DIR cannot be written to, or is locked"
    ledger_void "$1"
    return 0
  fi
  ledger_write "$@"
  if [ "$LEDGER_RECORDED" -eq 0 ]; then ledger_void "$1"; fi
  ledger_unlock
}

# ledger_write <result> <secs> <command> — with the lock held.
ledger_write() {
  local result="$1" secs="$2" command_string="$3"

  LEDGER_RECORDED=0
  ledger_read 1
  if [ "$LEDGER_BLOCKED" -eq 1 ]; then
    warn "the result was not recorded"
    return 0
  fi
  if ! LEDGER_TMP=$(mktemp "$LEDGER_DIR/ledger.XXXXXX" 2>/dev/null); then
    LEDGER_TMP=""
    warn "the result was not recorded: $LEDGER_DIR cannot be written to"
    return 0
  fi
  # The ledger goes in on stdin: a ledger of 2000 entries is past the limit on a
  # single argument. The entry is built in the same call, from --arg values, for
  # the same reason: a long command escaped twice would not fit either.
  # Past the cap the OLDEST of the other entries go; the entry just written never
  # does, whatever its timestamp says.
  if ! printf '%s' "$LEDGER_JSON" | jq -c \
    --arg key "$KEY" \
    --arg command "$command_string" \
    --arg result "$result" \
    --arg fingerprint "$FP" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson secs "$secs" \
    --argjson cap "$LEDGER_CAP" '
      {command: $command, result: $result, fingerprint: $fingerprint, at: $at, secs: $secs} as $entry
      | (.entries | del(.[$key]) | to_entries | sort_by(.value.at)) as $others
      | .entries = (
          (if ($others | length) > ($cap - 1)
           then $others[(($others | length) - ($cap - 1)):]
           else $others end
           | from_entries) + {($key): $entry})' >"$LEDGER_TMP" 2>/dev/null; then
    rm -f -- "$LEDGER_TMP"
    LEDGER_TMP=""
    warn "the result was not recorded: the ledger could not be rewritten"
    return 0
  fi
  if ! mv -f -- "$LEDGER_TMP" "$LEDGER_FILE" 2>/dev/null; then
    rm -f -- "$LEDGER_TMP"
    LEDGER_TMP=""
    warn "the result was not recorded: $LEDGER_FILE cannot be replaced"
    return 0
  fi
  LEDGER_TMP=""
  LEDGER_RECORDED=1
  # This record supersedes a void made before the lock was ours. One newer than
  # the lock was made by a FAIL that waited on this very write, and it stays.
  if [ -e "$LEDGER_DIR/void.$KEY" ] && ! [ "$LEDGER_DIR/void.$KEY" -nt "$LOCK_DIR" ]; then
    rm -f -- "$LEDGER_DIR/void.$KEY" 2>/dev/null || true
  fi
  ledger_prune_voids
}

# ledger_prune_voids — with the lock held, after a write: a void whose key the
# ledger no longer holds protects no PASS, so it goes, and there are never more
# markers than entries. The keys are read once, and only when a marker exists.
ledger_prune_voids() {
  local v held="" read_keys=0
  for v in "$LEDGER_DIR"/void.*; do
    if [ ! -e "$v" ]; then continue; fi
    if [ "$read_keys" -eq 0 ]; then
      held=$(jq -r '.entries | keys[]' "$LEDGER_FILE" 2>/dev/null) || return 0
      read_keys=1
    fi
    # A pattern match, not a here-string: one that could not be written (a full
    # disk) would read as "not held" and delete the voids that protect a PASS.
    case $'\n'"$held"$'\n' in
      *$'\n'"${v##*/void.}"$'\n'*) ;;
      *) rm -f -- "$v" 2>/dev/null || true ;;
    esac
  done
}

# shadow_append <result> <secs> <would_reuse> <command> — one line per shadow
# run, then the log is trimmed to its newest SHADOW_CAP lines through a temp file
# and a rename. A failure warns and changes nothing else.
shadow_append() {
  local result="$1" secs="$2" would="$3" command_string="$4" line lines log
  log="$LEDGER_DIR/shadow.log"

  line=$(jq -nc \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg command "$command_string" \
    --arg key "$KEY" \
    --argjson would "$would" \
    --arg result "$result" \
    --argjson secs "$secs" \
    '{at: $at, command: $command, key: $key, would_reuse: $would, result: $result, secs: $secs}')
  # A log whose last line lost its newline (a crash mid-append) would swallow the
  # next record: start on a new line in the same write.
  if [ -s "$log" ] && [ -n "$(tail -c 1 "$log" 2>/dev/null)" ]; then line=$'\n'"$line"; fi
  if ! mkdir -p -- "$LEDGER_DIR" 2>/dev/null || ! { printf '%s\n' "$line" >>"$log"; } 2>/dev/null; then
    warn "the shadow line was not recorded"
    return 0
  fi
  lines=$(wc -l <"$log" 2>/dev/null | tr -d ' ') || lines=0
  case "$lines" in '' | *[!0-9]*) return 0 ;; esac
  [ "$lines" -gt "$SHADOW_CAP" ] || return 0
  if ! SHADOW_TMP=$(mktemp "$LEDGER_DIR/shadow.XXXXXX" 2>/dev/null); then
    SHADOW_TMP=""
    warn "the shadow log was not trimmed"
    return 0
  fi
  if ! { tail -n "$SHADOW_CAP" "$log" >"$SHADOW_TMP" && mv -f -- "$SHADOW_TMP" "$log"; } 2>/dev/null; then
    rm -f -- "$SHADOW_TMP"
    warn "the shadow log was not trimmed"
  fi
  SHADOW_TMP=""
}

# find_never <command> — prints the first profile `never` entry the command holds
# as a literal substring (a pattern is never read), or nothing.
find_never() {
  local entry

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$1" in *"$entry"*)
      printf '%s' "$entry"
      return 0
      ;;
    esac
  done < <(jq -r '.never[]' <<<"$PROFILE_JSON")
  return 0
}

MODE=shadow
NEVER_ENTRY=""
RECORDABLE=0   # 1 when this run's result may be read from, and written to, the ledger
HIT=0          # 1 when the ledger holds a PASS for KEY
LAST="null"    # the ledger entry for KEY
REASON=""

# prepare <command> — what `run` and `lookup` both need: the fingerprint, the
# profile, the mode, the key and the ledger's verdict. The fingerprint is
# reported in every mode, `never` commands included. The key (and its probes) is
# built only where a result could be read or written. It only reads: an
# unreadable ledger is set aside by `ledger_record`, under the lock.
prepare() {
  local command_string="$1" mode_reason="" void_reason=""

  RECORDABLE=0
  HIT=0
  LAST="null"
  NEVER_ENTRY=""
  fingerprint
  load_profile
  MODE=$(jq -r '.mode' <<<"$PROFILE_JSON")
  KEY=""
  KEY_REASON=""
  if [ "$MODE" = off ]; then
    mode_reason="reuse is off"
  else
    NEVER_ENTRY=$(find_never "$command_string")
    if [ -n "$NEVER_ENTRY" ]; then
      mode_reason="the command holds a never-reuse entry: $NEVER_ENTRY"
    else
      build_key "$command_string"
    fi
  fi
  if [ -n "$KEY" ]; then
    resolve_ledger_dir
    if [ -n "$LEDGER_DIR" ]; then
      RECORDABLE=1
      ledger_read 0
      LAST=$(jq -c --arg k "$KEY" '.entries[$k] // null' <<<"$LEDGER_JSON")
      if jq -e '. != null and .result == "PASS"' <<<"$LAST" >/dev/null 2>&1; then HIT=1; fi
      # A dropped non-PASS voided the key: its older PASS is no hit, and says why.
      if [ "$HIT" -eq 1 ] && [ -e "$LEDGER_DIR/void.$KEY" ]; then
        HIT=0
        void_reason="the key is void: a later non-PASS for this command was not recorded"
      fi
    else
      mode_reason="$LEDGER_NOTE"
    fi
  fi
  REASON=$(join_reasons "$FP_REASON" "$PROFILE_REASON" "$mode_reason" "$KEY_REASON" "$void_reason")
}

# emit_run <decision> <would_reuse> <result> <exit> <evidence> <secs>
emit_run() {
  jq -nc \
    --arg mode "$MODE" \
    --arg decision "$1" \
    --argjson would "$2" \
    --arg result "$3" \
    --argjson exit "$4" \
    --arg evidence "$5" \
    --argjson secs "$6" \
    --arg fingerprint "$FP" \
    --arg key "$KEY" \
    --arg reason "$REASON" \
    '{
      mode: $mode,
      decision: $decision,
      would_reuse: $would,
      result: $result,
      exit: $exit,
      evidence: $evidence,
      secs: $secs,
      fingerprint: (if $fingerprint == "" then null else $fingerprint end),
      key: (if $key == "" then null else $key end),
      reason: $reason
    }'
}

cmd_run() {
  local fresh=0 limit=300 command_string result start secs would=false at

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fresh)
        fresh=1
        shift
        ;;
      --timeout)
        [ "$#" -ge 2 ] || usage_error "--timeout needs a number of seconds"
        case "$2" in '' | *[!0-9]*) usage_error "--timeout needs a whole number of seconds, got: $2" ;; esac
        [ "$2" -gt 0 ] || usage_error "--timeout must be greater than zero"
        limit="$2"
        shift 2
        ;;
      --) break ;;
      *) usage_error "run takes --fresh, --timeout <s> and -- <command>; got: $1" ;;
    esac
  done
  [ "${1:-}" = "--" ] || usage_error "run needs -- before the command"
  shift
  [ "$#" -gt 0 ] || usage_error "run needs a command after --"
  command_string="$*"
  [ -n "${command_string//[[:space:]]/}" ] || usage_error "run needs a command after --"

  prepare "$command_string"
  if [ "$HIT" -eq 1 ]; then would=true; fi

  # Only a PASS is ever a hit, and only in mode `on`: shadow measures, off and a
  # never-reuse command never look, and --fresh asks for a real run.
  if [ "$MODE" = on ] && [ "$HIT" -eq 1 ] && [ "$fresh" -eq 0 ]; then
    at=$(jq -r '.at' <<<"$LAST")
    emit_run reused true PASS 0 "reused: PASS recorded $at" 0
    return 0
  fi

  start=$SECONDS
  run_command "$command_string" "$limit"
  secs=$((SECONDS - start))

  result=FAIL
  if [ "$RUN_EXIT" -eq 0 ]; then result=PASS; fi

  if [ "$RECORDABLE" -eq 1 ] && [ "$RUN_STARTED" -eq 1 ]; then
    ledger_record "$result" "$secs" "$command_string"
    if [ "$MODE" = shadow ]; then shadow_append "$result" "$secs" "$would" "$command_string"; fi
  fi

  emit_run ran "$would" "$result" "$RUN_EXIT" "$RUN_EVIDENCE" "$secs"
  [ "$result" = PASS ]
}

cmd_lookup() {
  local command_string would=false

  [ "${1:-}" = "--" ] || usage_error "lookup needs -- before the command"
  shift
  [ "$#" -gt 0 ] || usage_error "lookup needs a command after --"
  command_string="$*"
  [ -n "${command_string//[[:space:]]/}" ] || usage_error "lookup needs a command after --"

  prepare "$command_string"
  if [ "$HIT" -eq 1 ]; then would=true; fi

  jq -nc \
    --arg mode "$MODE" \
    --argjson would "$would" \
    --arg fingerprint "$FP" \
    --arg key "$KEY" \
    --argjson last "$LAST" \
    --arg reason "$REASON" \
    '{
      mode: $mode,
      would_reuse: $would,
      fingerprint: (if $fingerprint == "" then null else $fingerprint end),
      key: (if $key == "" then null else $key end),
      last: $last,
      reason: (if $reason == "" then null else $reason end)
    }'
}

cmd_stats() {
  local log

  [ "$#" -eq 0 ] || usage_error "stats takes no arguments"
  TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
  resolve_ledger_dir
  log="$LEDGER_DIR/shadow.log"
  if [ -z "$LEDGER_DIR" ]; then
    warn "no shadow log: ${LEDGER_NOTE}"
    log=/dev/null
  elif [ ! -f "$log" ]; then
    log=/dev/null
  elif [ ! -r "$log" ]; then
    warn "the shadow log cannot be read"
    log=/dev/null
  fi
  jq -Rn '
    [inputs | fromjson? | select(type == "object")] as $lines
    | ($lines | map(select(.would_reuse == true))) as $would
    | {
        runs: ($lines | length),
        would_reuse: ($would | length),
        agreed: ($would | map(select(.result == "PASS")) | length),
        disagreed: ($would | map(select(.result == "FAIL") | {command, at})),
        secs_reusable: ($would | map(.secs | numbers) | add // 0)
      }' <"$log"
}

# --- profile --detect ---------------------------------------------------------

DETECT_TOOLS=""    # one probe per line
DETECT_INPUTS=""   # one path per line

# add_probe <probe> — only when the probe's binary is on PATH, and once.
add_probe() {
  local probe="$1" bin="${1%% *}"

  command -v "$bin" >/dev/null 2>&1 || return 0
  case $'\n'"$DETECT_TOOLS" in *$'\n'"$probe"$'\n'*) return 0 ;; esac
  DETECT_TOOLS+="$probe"$'\n'
}

# has_manifest <glob> — a manifest by name or glob, at the project's top level.
has_manifest() {
  (cd "$DETECT_BASE" && compgen -G "$1" >/dev/null 2>&1)
}

DETECT_BASE=""

cmd_profile() {
  local pm name f base_name

  [ "$#" -eq 1 ] && [ "$1" = "--detect" ] || usage_error "profile takes --detect and nothing else"

  # The top level when there is a work tree, else the current directory: the
  # manifests are read from there.
  TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
  DETECT_BASE="${TOP:-$PWD}"

  # --- tools: one probe per toolchain whose manifest exists and whose binary is
  # on PATH. The probe text is what the key runs later with `bash -c`.
  if has_manifest package.json; then
    add_probe "node --version"
    if pm=$(jq -er '.packageManager // empty' "$DETECT_BASE/package.json" 2>/dev/null) && [ -n "$pm" ]; then
      name="${pm%%@*}"
      # The value comes from a file in the repository and ends up in a command:
      # only a plain tool name is accepted.
      case "$name" in
        '' | *[!A-Za-z0-9._-]*) warn "package.json packageManager is not a plain tool name; its probe is skipped" ;;
        *) add_probe "$name --version" ;;
      esac
    elif ! jq -e . "$DETECT_BASE/package.json" >/dev/null 2>&1; then
      warn "package.json is not valid JSON; the packageManager probe is skipped"
    fi
  fi
  if has_manifest go.mod; then add_probe "go version"; fi
  if has_manifest Cargo.toml; then add_probe "rustc --version"; fi
  if has_manifest pyproject.toml || has_manifest 'requirements*.txt'; then add_probe "python3 --version"; fi
  if has_manifest composer.json; then add_probe "php --version"; fi
  if has_manifest 'build.gradle*' || has_manifest pom.xml; then add_probe "java -version"; fi
  if has_manifest Gemfile; then add_probe "ruby --version"; fi
  if has_manifest 'deno.json*'; then add_probe "deno --version"; fi

  # --- inputs: gitignored environment and local-configuration files outside
  # dependency directories. The two greps run at C speed over a list that can
  # hold tens of thousands of dependency files; the loop sees only what is left.
  if [ -n "$TOP" ]; then
    while IFS= read -r -d '' f; do
      case "$f" in *$'\n'*) continue ;; esac
      base_name="${f##*/}"
      case "$base_name" in
        .env | .env.* | .dev.vars | *.local.json | *.local.yaml | *.local.yml | *.local.toml | *.local.php)
          DETECT_INPUTS+="$f"$'\n'
          ;;
      esac
    done < <(git -C "$TOP" ls-files -z --others --ignored --exclude-standard 2>/dev/null |
      { grep -zvE '(^|/)(node_modules|vendor)/' || true; } |
      { grep -zE '(^|/)(\.env|\.env\.[^/]*|\.dev\.vars|[^/]*\.local\.(json|yaml|yml|toml|php))$' || true; })
  else
    warn "not a git work tree: no inputs are proposed"
  fi

  jq -n \
    --arg tools "$DETECT_TOOLS" \
    --arg inputs "$(printf '%s' "$DETECT_INPUTS" | LC_ALL=C sort -u)" \
    '{
      version: 1,
      mode: "shadow",
      tools: ($tools | split("\n") | map(select(length > 0))),
      inputs: ($inputs | split("\n") | map(select(length > 0))),
      never: []
    }'
}

[ "$#" -gt 0 ] || usage_error "a subcommand is required"

sub="$1"
shift
case "$sub" in
  lookup) cmd_lookup "$@" ;;
  run) cmd_run "$@" ;;
  stats) cmd_stats "$@" ;;
  profile) cmd_profile "$@" ;;
  *) usage_error "unknown subcommand: $sub" ;;
esac
