#!/usr/bin/env bash
# Runs a story's Validation commands and generated-gate commands, and writes the
# Auditor's Part 1 report — so the deterministic half of validation costs seconds
# instead of a sub-agent's turns.
#
#   validate-run.sh --story <dir> [--only <id,id,...>] [--timeout <s>] [--fresh]
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
# Each command goes through check-reuse.sh run: in the project's reuse mode `on`, a
# PASS recorded for the same command on the same code is reused instead of run.
# --fresh runs every command again. What this script checks itself (the Tests
# path, the Commit in git log) is checked on every run, reused or not.
#
# --only re-runs the named entries (sub-task ids, or gate:<text prefix>) and keeps
# every other entry of the previous run: a revalidation re-checks the failures,
# never the whole story. A kept entry that PASSED is kept only on the code it
# passed on (its recorded fingerprint equals the current one); on changed code, or
# with no fingerprint to compare, it runs again. SKIP, JUDGE and FAIL entries are
# kept as they were. It needs a previous full run: with none it exits 2.
#
# Writes .draft/validation-run.json (the machine form; every entry also carries
# `reused` and the `fingerprint` it was settled on) and
# .draft/validation-report.yaml (the schema validate-mode.md defines, with
# verdict pass | fail | pending — pending while a JUDGE entry is open; each
# result and gate adds `reused:`).
# Output: one JSON line {verdict, pass, fail, skip, judge, report}.
# Exit 0 on pass or pending, 1 on fail, 2 on bad usage.

set -euo pipefail

usage() { sed -n '5,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STORY="" ONLY="" TIMEOUT=300 FRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --only) ONLY="${2-}"; shift 2 ;;
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
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
CHECK_REUSE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-reuse.sh"
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

# Runs one command through check-reuse.sh and sets RUN_CODE, RUN_EVIDENCE,
# RUN_REUSED and RUN_FP (a JSON value). A missing or invalid JSON line is a
# failed run (exit 1) whose evidence is what the runner wrote to stderr.
run_check() {  # <command>
  local errf line cmd=(bash "$CHECK_REUSE" run --timeout "$TIMEOUT")
  [ "$FRESH" -eq 1 ] && cmd+=(--fresh)
  errf="$(mktemp)"
  line="$(cd "$ROOT" && "${cmd[@]}" -- "$1" </dev/null 2>"$errf")" || true
  if printf '%s' "$line" | jq -e 'type == "object" and (.exit | type) == "number" and (.result == "PASS" or .result == "FAIL")' >/dev/null 2>&1; then
    RUN_CODE="$(printf '%s' "$line" | jq -r '.exit')"
    RUN_EVIDENCE="$(printf '%s' "$line" | jq -r '.evidence // ""')"
    RUN_REUSED="$(printf '%s' "$line" | jq -r '.decision == "reused"')"
    RUN_FP="$(printf '%s' "$line" | jq -c '.fingerprint // null')"
  else
    RUN_CODE=1 RUN_REUSED=false RUN_FP=null
    RUN_EVIDENCE="check-reuse.sh gave no result: $(tr '\r\n' '  ' <"$errf" | cut -c1-160)"
  fi
  rm -f "$errf"
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
  local kind=$1 id=$2 box=$3 val=$4 tst=$5 cmt=$6 more=$7 result detail qualifier="" code last reused=false fp=null
  if [ "$box" = "~" ]; then
    result=SKIP qualifier="$val" detail="closed without the work"
  elif [ "$box" = " " ] && [ "$kind" = sub ]; then
    return 0  # not done yet; an open gate is exactly what validation settles
  elif [ -z "$val" ] || [ "${val#!}" != "$val" ] || ! runnable "$val"; then
    result=JUDGE detail="${val#!}"; [ -z "$detail" ] && detail="no command in the text"
  else
    run_check "$val"; code="$RUN_CODE" last="$RUN_EVIDENCE" reused="$RUN_REUSED" fp="$RUN_FP"
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
    --argjson reused "$reused" --argjson fp "$fp" \
    '{kind: $kind, id: $id, result: $result, qualifier: (if $q == "" then null else $q end), detail: $detail,
      reused: $reused, fingerprint: $fp}'
}

# --only keeps the entries of a previous run; with none there is nothing to keep,
# and a report built from the named entries alone would pass a story on a fraction
# of its checks. Refuse before anything is run or written.
if [ -n "$ONLY" ] && [ ! -f "$JSON" ]; then
  echo "validate-run.sh: --only needs a previous full run; run without --only first" >&2; exit 2
fi
PREV='[]'
[ -n "$ONLY" ] && [ -f "$JSON" ] && PREV="$(jq -c '.entries' "$JSON")"

# Under --only a previous PASS is kept only on the code it passed on. The current
# fingerprint is whatever `check-reuse.sh lookup` reports; when lookup is unusable
# (a non-zero exit, no output, invalid JSON, a null fingerprint) it is unknown, and
# every previous PASS runs again: "unchanged" is a claim only a fingerprint can make.
CUR_FP=""
if [ -n "$ONLY" ]; then
  lookup_line="$(cd "$ROOT" && bash "$CHECK_REUSE" lookup -- true 2>/dev/null)" || lookup_line=""
  CUR_FP="$(printf '%s' "$lookup_line" | jq -r 'if type == "object" and (.fingerprint | type) == "string" then .fingerprint else "" end' 2>/dev/null)" || CUR_FP=""
fi

stale() {  # <previous entry> — does an unselected entry have to run again?
  printf '%s' "$1" | jq -e --arg fp "$CUR_FP" \
    '.result == "PASS" and ($fp == "" or (.fingerprint // null) != $fp)' >/dev/null 2>&1
}

NEW="$(entries | while IFS=$'\x1f' read -r kind id box val tst cmt more; do
  if selected "$kind" "$id"; then check "$kind" "$id" "$box" "$val" "$tst" "$cmt" "$more"
  else
    prev="$(printf '%s' "$PREV" | jq -c --arg k "$kind" --arg i "$id" '.[] | select(.kind == $k and .id == $i)')"
    if [ -n "$prev" ] && stale "$prev"; then check "$kind" "$id" "$box" "$val" "$tst" "$cmt" "$more"
    elif [ -n "$prev" ]; then printf '%s\n' "$prev"; fi
  fi
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
    "  - task: \(.id | tojson)", "    result: \(.result)", "    qualifier: \(.qualifier // null | tojson)", "    detail: \(.detail | tojson)", "    reused: \(.reused // false)"),
  "gates:",
  (.entries[] | select(.kind == "gate") |
    "  - gate: \(.id | tojson)", "    result: \(.result)", "    evidence: \(.detail | tojson)", "    reused: \(.reused // false)")
' "$JSON" > "$YAML"

jq -c --arg report "$YAML" '{verdict, pass: ([.entries[] | select(.result == "PASS")] | length),
  fail: ([.entries[] | select(.result == "FAIL")] | length), skip: ([.entries[] | select(.result == "SKIP")] | length),
  judge: ([.entries[] | select(.result == "JUDGE")] | length), report: $report}' "$JSON"
[ "$verdict" = fail ] && exit 1
exit 0
