#!/usr/bin/env bash
# Runs a story's Validation commands and generated-gate commands, and writes the
# Auditor's Part 1 report — so the deterministic half of validation costs seconds
# instead of a sub-agent's turns.
#
#   validate-run.sh --story <dir> [--only <id,id,...>] [--timeout <s>]
#
# Reads tasks.md. Every [x] sub-task's `Validation:` field is run from its first
# backtick span — and a field with more than one span is JUDGE once that first
# command passes, since the script cannot know what "with the server running"
# asks of the second; its `Tests:` path must exist; its group's `Commit:` message must
# be in git log. A [~] sub-task is SKIP with its qualifier. Every Quality Gate
# whose text carries a backtick command is run the same way. What cannot be run
# — a prose check, a span that is a file name, a span holding a `<placeholder>`,
# a gate with no command — is JUDGE:
# the Auditor settles those, and only those.
#
# --only re-runs the named entries (sub-task ids, or gate:<text prefix>) and keeps
# every other entry of the previous run: a revalidation re-checks the failures,
# never the whole story.
#
# Writes .draft/validation-run.json (the machine form) and
# .draft/validation-report.yaml (the schema validate-mode.md defines, with
# verdict pass | fail | pending — pending while a JUDGE entry is open).
# Output: one JSON line {verdict, pass, fail, skip, judge, report}.
# Exit 0 on pass or pending, 1 on fail, 2 on bad usage.

set -euo pipefail

usage() { sed -n '5,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STORY="" ONLY="" TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --only) ONLY="${2-}"; shift 2 ;;
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "validate-run.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$STORY" ] || [ ! -f "$STORY/tasks.md" ]; then
  echo "validate-run.sh: --story <dir> is required and must hold tasks.md" >&2; exit 2
fi
case "$TIMEOUT" in '' | *[!0-9]*) echo "validate-run.sh: --timeout takes whole seconds" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "validate-run.sh: jq is required" >&2; exit 2; }

STORY="$(cd "$STORY" && pwd)"
# The project root holds .epico/: stories live at .epico/stories/<dir> or
# .epico/archive/<dir>, so it is three levels up.
ROOT="$(cd "$STORY/../../.." && pwd)"
DRAFT="$STORY/.draft"
JSON="$DRAFT/validation-run.json" YAML="$DRAFT/validation-report.yaml"
mkdir -p "$DRAFT"

# One row per entry, fields split by \x1f: kind, id, box, command-or-text,
# tests-path, commit-msg, and the whole text when it holds more than one span. Not TAB: `read` folds runs of whitespace separators,
# which shifts every field after an empty one.
# Sub-task fields are collected until the next box; a group's Commit applies to
# the sub-task it is written under (the last one of the group, by convention).
entries() {
  awk '
    function flush() {
      if (id != "") printf "sub\037%s\037%s\037%s\037%s\037%s\037%s\n", id, box, val, tst, cmt, more
      id = ""; val = ""; tst = ""; cmt = ""; more = ""
    }
    function span(s,   a) { if (match(s, /`[^`]+`/)) return substr(s, RSTART + 1, RLENGTH - 2); return "" }
    function spans(s,   c) { c = s; return gsub(/`[^`]+`/, "", c) }
    /^## Quality Gates/ { flush(); gates = 1; next }
    /^## / { flush(); gates = 0; next }
    gates && /^- \[[ x~]\] / {
      b = substr($0, 4, 1); t = substr($0, 7)
      printf "gate\037%s\037%s\037%s\037\037\037%s\n", t, b, span(t), (spans(t) > 1 ? t : ""); next
    }
    /^[[:space:]]*- \[[ x~]\] [0-9]+\.[0-9]+/ {
      flush(); box = substr($0, index($0, "[") + 1, 1)
      s = $0; sub(/^[[:space:]]*- \[[ x~]\] /, "", s); split(s, w, /[ :—-]/); id = w[1]
      if (box == "~") { q = $0; sub(/.*\(/, "", q); sub(/[:)].*/, "", q); val = q }
      next
    }
    /^- \[[ x~]\] / { flush(); next }
    id != "" && /^[[:space:]]+- Validation:/ && box != "~" {
      val = span($0); if (val == "") val = "!" substr($0, index($0, ":") + 2)
      if (spans($0) > 1) more = substr($0, index($0, ":") + 2)
    }
    id != "" && /^[[:space:]]+- Tests:/ { t = $0; if (index(t, "·")) { t = substr(t, index(t, "·")); tst = span(t) } }
    id != "" && /^[[:space:]]+- Commit:/ { c = $0; sub(/^[^"]*"/, "", c); sub(/".*$/, "", c); cmt = c }
    END { flush() }' "$STORY/tasks.md"
}

runnable() {  # <command> — is its first word something the shell can run?
  local first
  # A `<job>`-style placeholder means the span describes a command rather than
  # being one: run, it fails on the placeholder and reads as the check failing.
  # A redirection (`cmd <in >out`) has a space or no closing `>` and passes.
  if printf '%s' "$1" | grep -qE '<[A-Za-z][A-Za-z0-9_-]*>'; then return 1; fi
  first="$(printf '%s' "$1" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//' | awk '{print $1}')"
  [ -n "$first" ] || return 1
  case "$first" in
    */*) [ -x "$ROOT/$first" ] || [ -x "$first" ] ;;
    *) command -v "$first" >/dev/null 2>&1 ;;
  esac
}

# Output goes to a file, not a pipe, and the command runs in its own session:
# a `cargo run &` inside a gate kept a captured pipe open until the timeout
# (300 s lost in a rust run). The session is killed once the command returns,
# so a server it started never outlives its check.
run_cmd() {  # <command> — prints "<exit>\t<evidence line>"
  local log sidf code evidence
  log="$(mktemp)" sidf="$(mktemp)"
  set +e
  # --fork makes setsid succeed even where this shell's job is a group leader;
  # the new session's leader writes its own pid, which names the group to kill.
  # shellcheck disable=SC2016  # $$ and $0 belong to the inner bash
  (cd "$ROOT" && setsid --fork --wait bash -c 'echo "$$" > "$0"; exec timeout "$1" bash -c "$2"' "$sidf" "$TIMEOUT" "$1") </dev/null >"$log" 2>&1
  code=$?
  set -e
  if [ -s "$sidf" ]; then kill -TERM -- "-$(cat "$sidf")" 2>/dev/null || true; fi
  if [ "$code" -eq 124 ]; then
    evidence="timed out after ${TIMEOUT}s"
  else
    evidence="$(tr -d '\r' < "$log" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | runner_totals)"
  fi
  rm -f "$log" "$sidf"
  printf '%s\t%s\n' "$code" "$(printf '%s' "$evidence" | cut -c1-200)"
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

selected() {  # <kind> <id> — is this entry re-run under --only?
  [ -z "$ONLY" ] && return 0
  local want IFS=','
  for want in $ONLY; do
    if [ "$1" = sub ] && [ "$want" = "$2" ]; then return 0; fi
    if [ "$1" = gate ] && [ "${want#gate:}" != "$want" ] && [ "${2#"${want#gate:}"}" != "$2" ]; then return 0; fi
  done
  return 1
}

check() {  # <kind> <id> <box> <value> <tests> <commit> <whole text if compound> — prints one JSON entry
  local kind=$1 id=$2 box=$3 val=$4 tst=$5 cmt=$6 more=$7 result detail qualifier="" res code last
  if [ "$box" = "~" ]; then
    result=SKIP qualifier="$val" detail="closed without the work"
  elif [ "$box" = " " ] && [ "$kind" = sub ]; then
    return 0  # not done yet; an open gate is exactly what validation settles
  elif [ -z "$val" ] || [ "${val#!}" != "$val" ] || ! runnable "$val"; then
    result=JUDGE detail="${val#!}"; [ -z "$detail" ] && detail="no command in the text"
  else
    res="$(run_cmd "$val")"; code="${res%%$'\t'*}"; last="${res#*$'\t'}"
    if [ "$code" -eq 0 ]; then result=PASS; else result=FAIL; fi
    detail="\`$val\` exit $code${last:+ — $last}"
    if [ "$result" = PASS ] && [ -n "$more" ]; then result=JUDGE detail="$detail; the rest is not run: $more"; fi
  fi
  if [ "$kind" = sub ] && { [ "$result" = PASS ] || [ "$result" = JUDGE ]; }; then
    if [ -n "$tst" ] && [ ! -e "$ROOT/$tst" ]; then result=FAIL detail="test file missing: $tst"; fi
    if [ -n "$cmt" ] && ! git -C "$ROOT" log --fixed-strings --grep="$cmt" -1 --format=%h 2>/dev/null | grep -q .; then
      result=FAIL detail="commit not found: \"$cmt\""
    fi
  fi
  jq -nc --arg kind "$kind" --arg id "$id" --arg result "$result" --arg detail "$detail" --arg q "$qualifier" \
    '{kind: $kind, id: $id, result: $result, qualifier: (if $q == "" then null else $q end), detail: $detail}'
}

# --only keeps the entries of a previous run; with none there is nothing to keep,
# and a report built from the named entries alone would pass a story on a fraction
# of its checks. Refuse before anything is run or written.
if [ -n "$ONLY" ] && [ ! -f "$JSON" ]; then
  echo "validate-run.sh: --only needs a previous full run; run without --only first" >&2; exit 2
fi
PREV='[]'
[ -n "$ONLY" ] && [ -f "$JSON" ] && PREV="$(jq -c '.entries' "$JSON")"
NEW="$(entries | while IFS=$'\x1f' read -r kind id box val tst cmt more; do
  if selected "$kind" "$id"; then check "$kind" "$id" "$box" "$val" "$tst" "$cmt" "$more"
  else printf '%s' "$PREV" | jq -c --arg k "$kind" --arg i "$id" '.[] | select(.kind == $k and .id == $i)'; fi
done | jq -sc '.')"

# "All task validations pass" is the sub-task results themselves: derived on
# every run — a --only revalidation included — so the Auditor never re-judges
# what the runs just proved, and a stale FAIL never outlives its fix.
NEW="$(printf '%s' "$NEW" | jq -c '
  ([.[] | select(.kind == "sub")]) as $subs
  | map(if .kind == "gate" and (.id | startswith("All task validations pass")) then
      if any($subs[]; .result == "FAIL") then .result = "FAIL" | .detail = "a sub-task validation failed"
      elif any($subs[]; .result == "JUDGE") then .result = "JUDGE" | .detail = "waits on the JUDGE sub-tasks"
      else .result = "PASS" | .detail = "no FAIL in results[]" end
    else . end)')"
verdict="$(printf '%s' "$NEW" | jq -r 'if any(.[]; .result == "FAIL") then "fail" elif any(.[]; .result == "JUDGE") then "pending" else "pass" end')"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg story "$(basename "$STORY")" --arg at "$NOW" --arg verdict "$verdict" --argjson entries "$NEW" \
  '{story: $story, generated_at: $at, generated_by: "epico-validate-run", verdict: $verdict, entries: $entries}' > "$JSON"

# JSON strings are valid YAML double-quoted scalars, so every value goes out
# through tojson and needs no escaping of its own.
jq -r '
  "story: \(.story | tojson)",
  "generated_at: \(.generated_at | tojson)",
  "generated_by: epico-validate-run",
  "verdict: \(.verdict)",
  "results:",
  (.entries[] | select(.kind == "sub") |
    "  - task: \(.id | tojson)", "    result: \(.result)", "    qualifier: \(.qualifier // null | tojson)", "    detail: \(.detail | tojson)"),
  "gates:",
  (.entries[] | select(.kind == "gate") |
    "  - gate: \(.id | tojson)", "    result: \(.result)", "    evidence: \(.detail | tojson)")
' "$JSON" > "$YAML"

jq -c --arg report "$YAML" '{verdict, pass: ([.entries[] | select(.result == "PASS")] | length),
  fail: ([.entries[] | select(.result == "FAIL")] | length), skip: ([.entries[] | select(.result == "SKIP")] | length),
  judge: ([.entries[] | select(.result == "JUDGE")] | length), report: $report}' "$JSON"
[ "$verdict" = fail ] && exit 1
exit 0
