#!/usr/bin/env bash
# Decides whether a check (a command that proves something about the code) has
# to run again, or whether its last PASS on the very same code still stands.
#
# Usage: bash scripts/check-reuse.sh run [--fresh] [--timeout <s>] -- <command>
#        bash scripts/check-reuse.sh lookup -- <command>
#        (stats and profile arrive in later sub-tasks of story 030; until then
#         they are refused as usage errors)
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
#      into a temp file — the copy keeps git's stat cache, an empty temp index
#      would re-hash the whole tree;
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

USAGE='Usage: check-reuse.sh run [--fresh] [--timeout <s>] -- <command> | lookup -- <command>'

usage_error() {
  printf '%s\n' "$1" >&2
  printf '%s\n' "$USAGE" >&2
  exit 2
}

IDX=""         # the temporary copy of the index
PROBE_TMP=""   # the file a probe's output is captured in
RUN_LOG=""     # the file the checked command's output is captured in
RUN_SID=""     # the file the command's session leader writes its pid to
cleanup() {
  if [ -n "$IDX" ]; then rm -f -- "$IDX"; fi
  if [ -n "$PROBE_TMP" ]; then rm -f -- "$PROBE_TMP"; fi
  if [ -n "$RUN_LOG" ]; then rm -f -- "$RUN_LOG"; fi
  if [ -n "$RUN_SID" ]; then rm -f -- "$RUN_SID"; fi
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
    if ! cp -- "$gitidx" "$IDX"; then
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

# run_command <command> <timeout> — runs the command and sets RUN_EXIT and
# RUN_EVIDENCE. Output goes to a file, not a pipe, and the command runs in its
# own session: a `cargo run &` inside a gate once kept a captured pipe open until
# the timeout (300 s lost in a rust run). The session is killed once the command
# returns, so a server it started never outlives its check.
run_command() {
  local command_string="$1" limit="$2" code=0 dir

  dir="${TOP:-$PWD}"
  RUN_LOG=$(mktemp "${TMPDIR:-/tmp}/epico-reuse.XXXXXX") || {
    RUN_LOG=""
    RUN_EXIT=1
    RUN_EVIDENCE="no temporary file could be created"
    return 0
  }
  RUN_SID=$(mktemp "${TMPDIR:-/tmp}/epico-reuse.XXXXXX") || {
    RUN_SID=""
    RUN_EXIT=1
    RUN_EVIDENCE="no temporary file could be created"
    return 0
  }
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

cmd_run() {
  local fresh=0 limit=300 command_string reason mode result start secs

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

  fingerprint
  load_profile
  build_key "$command_string"
  mode=$(jq -r '.mode' <<<"$PROFILE_JSON")
  reason=$(join_reasons "$FP_REASON" "$PROFILE_REASON" "$KEY_REASON")

  start=$SECONDS
  run_command "$command_string" "$limit"
  secs=$((SECONDS - start))

  result=FAIL
  if [ "$RUN_EXIT" -eq 0 ]; then result=PASS; fi

  # shellcheck disable=SC2034  # $fresh is acted on by the ledger, in 3.2
  : "$fresh"
  jq -nc \
    --arg mode "$mode" \
    --arg result "$result" \
    --argjson exit "$RUN_EXIT" \
    --arg evidence "$RUN_EVIDENCE" \
    --argjson secs "$secs" \
    --arg fingerprint "$FP" \
    --arg key "$KEY" \
    --arg reason "$reason" \
    '{
      mode: $mode,
      decision: "ran",
      would_reuse: false,
      result: $result,
      exit: $exit,
      evidence: $evidence,
      secs: $secs,
      fingerprint: (if $fingerprint == "" then null else $fingerprint end),
      key: (if $key == "" then null else $key end),
      reason: $reason
    }'
  [ "$result" = PASS ]
}

cmd_lookup() {
  local command_string reason mode

  [ "${1:-}" = "--" ] || usage_error "lookup needs -- before the command"
  shift
  [ "$#" -gt 0 ] || usage_error "lookup needs a command after --"
  command_string="$*"
  [ -n "${command_string//[[:space:]]/}" ] || usage_error "lookup needs a command after --"

  fingerprint
  load_profile
  build_key "$command_string"
  mode=$(jq -r '.mode' <<<"$PROFILE_JSON")
  reason=$(join_reasons "$FP_REASON" "$PROFILE_REASON" "$KEY_REASON")

  jq -nc \
    --arg mode "$mode" \
    --arg fingerprint "$FP" \
    --arg key "$KEY" \
    --arg reason "$reason" \
    '{
      mode: $mode,
      would_reuse: false,
      fingerprint: (if $fingerprint == "" then null else $fingerprint end),
      key: (if $key == "" then null else $key end),
      last: null,
      reason: (if $reason == "" then null else $reason end)
    }'
}

[ "$#" -gt 0 ] || usage_error "a subcommand is required"

sub="$1"
shift
case "$sub" in
  lookup) cmd_lookup "$@" ;;
  run) cmd_run "$@" ;;
  stats | profile) usage_error "'$sub' is not available yet" ;;
  *) usage_error "unknown subcommand: $sub" ;;
esac
