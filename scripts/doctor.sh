#!/usr/bin/env bash
# Read-only health check of a project's .epico/ tree. Prints one JSON object
# (default) or one summary line (--summary), and changes nothing on disk.
#
#   error   — something an Epico mode will trip over: no constitution or one
#             missing a required section, a story with no tasks.md, a
#             standard/full story with no story.md.
#   warning — drift that degrades a mode without breaking it: EPICO.md absent
#             or behind the disk, no .gitpolicy, archived stories with no
#             manifest, a leftover .draft/red-scratch/, an untracked .epico/
#             copy inside a git worktree, a dormant draft, a stall, and no
#             .epico/reuse-profile.json (init --repair writes it).
#
# .draft/meta.yaml is required only while a story has no tasks.md: it is the
# planning record, and a planned story whose .draft/ was cleaned up is healthy.
#
# A STALL is an in-progress story whose last progress note (.draft/progress.log,
# written by epico-progress) is older than --stall-minutes. A story with no log
# predates the notes and is never called stalled.
#
# --summary is what SessionStart and the story list call: silent when there is
# no .epico/ or nothing to report, one line otherwise. Exit 0 whenever the check
# ran, whatever it found; 2 on bad usage.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: doctor.sh [--epico-dir <dir>] [--stale-days <n>] [--stall-minutes <n>] [--summary]

  --epico-dir <dir>      The .epico directory. Default: the nearest .epico at or above the cwd.
  --stale-days <n>      A story with no boxes untouched this many days is a dormant draft. Default 7.
  --stall-minutes <n>   An in-progress story with no progress note this long is stalled. Default 15.
  --summary             One line instead of JSON; nothing when there is nothing to report.
USAGE
}

EPICO_DIR="" STALE_DAYS=7 STALL_MIN=15 SUMMARY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --epico-dir | --epic-dir) EPICO_DIR="${2-}"; shift 2 ;;
    --stale-days) STALE_DAYS="${2-}"; shift 2 ;;
    --stall-minutes) STALL_MIN="${2-}"; shift 2 ;;
    --summary) SUMMARY=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "doctor.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$STALE_DAYS" =~ ^[0-9]+$ ]] || STALE_DAYS=7
[[ "$STALL_MIN" =~ ^[0-9]+$ ]] || STALL_MIN=15

LEGACY=""
if [ -z "$EPICO_DIR" ]; then
  d=$PWD
  while :; do
    [ -d "$d/.epico" ] && { EPICO_DIR="$d/.epico"; break; }
    # A .epic/ from before the rename to Epico, nearer than any .epico/.
    [ -d "$d/.epic" ] && { LEGACY="$d/.epic"; break; }
    [ "$d" = "/" ] && break
    d=$(dirname "$d")
  done
fi
if [ -n "$LEGACY" ]; then
  detail="$LEGACY/ predates the rename to Epico — run epico-migrate-dir to move it to .epico/"
  if $SUMMARY; then echo "epico-doctor: 1 error(s), 0 warning(s) — $detail"; exit 0; fi
  jq -n --arg t "$LEGACY" --arg d "$detail" \
    '{epico_dir: null, status: "legacy", errors: 1, warnings: 0, findings: [{severity: "error", check: "legacy-layout", target: $t, detail: $d}]}'
  exit 0
fi
if [ -z "$EPICO_DIR" ] || [ ! -d "$EPICO_DIR" ]; then
  $SUMMARY && exit 0
  jq -n '{epico_dir: null, status: "absent", errors: 0, warnings: 0, findings: []}'
  exit 0
fi
EPICO_DIR=$(cd "$EPICO_DIR" && pwd)
ROOT=$(dirname "$EPICO_DIR")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

FINDINGS=()
add() { FINDINGS+=("$(jq -cn --arg s "$1" --arg c "$2" --arg t "$3" --arg d "$4" '{severity: $s, check: $c, target: $t, detail: $d}')"); }

# front <file> <key> — the value of <key> in the file's leading frontmatter.
front() {
  [ -f "$1" ] || return 0
  awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    NR > 1 { if (index($0, k ":") == 1) { v = substr($0, length(k) + 2); gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit } }' "$1"
}

# --- Project files ---
C="$EPICO_DIR/constitution.md"
if [ ! -f "$C" ]; then
  add error constitution .epico/constitution.md "missing — run init to write it"
else
  for h in Defaults Quality; do
    grep -q "^## ${h}[[:space:]]*$" "$C" || add error constitution .epico/constitution.md "no '## $h' section — re-run init to add it"
  done
fi

[ -f "$EPICO_DIR/.gitpolicy" ] || add warning gitpolicy .epico/.gitpolicy "missing — init records whether .epico/ is tracked"

if [ ! -f "$EPICO_DIR/EPICO.md" ]; then
  add warning index .epico/EPICO.md "missing — run epico-index"
else
  # Regenerate into a scratch copy that sees the same stories/ and archive/.
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT
  mkdir "$T/.epico"
  cp "$EPICO_DIR/EPICO.md" "$T/.epico/EPICO.md"
  for s in stories archive; do [ -e "$EPICO_DIR/$s" ] && ln -s "$EPICO_DIR/$s" "$T/.epico/$s"; done
  if bash "$SCRIPT_DIR/epico-index.sh" --epico-dir "$T/.epico" >/dev/null 2>&1; then
    cmp -s "$EPICO_DIR/EPICO.md" "$T/.epico/EPICO.md" || add warning index .epico/EPICO.md "behind the disk — run epico-index"
  fi
fi

if [ -d "$EPICO_DIR/archive" ] && [ -n "$(find "$EPICO_DIR/archive" -mindepth 1 -maxdepth 1 -type d -print -quit)" ] &&
   [ ! -f "$EPICO_DIR/archive/manifest.yaml" ]; then
  add warning manifest .epico/archive/manifest.yaml "missing while archived stories exist"
fi

if [ -f "$ROOT/CLAUDE.md" ] || [ -f "$EPICO_DIR/constitution.md" ]; then
  if ! CM=$(bash "$SCRIPT_DIR/claude-md.sh" check --root "$ROOT" 2>/dev/null); then
    if printf '%s' "$CM" | jq -e '.present == true' >/dev/null 2>&1; then
      add warning claude-md CLAUDE.md "the Epico block is stale — run /epico:epico init --repair"
    else
      add warning claude-md CLAUDE.md "no Epico block — run /epico:epico init --repair"
    fi
  fi
fi

# The reuse profile is read-only for epico-check and written only by init; its
# absence means shadow mode with empty lists, so it is a warning, never an error.
[ -f "$EPICO_DIR/reuse-profile.json" ] || add warning reuse-profile .epico/reuse-profile.json "no reuse profile — run /epico:epico init --repair"

# --- Stories ---
NOW=$(date +%s)
# newest_mtime <dir> — epoch of the most recently modified file under <dir>
# (GNU stat, then BSD stat); NOW when there is no file, so empty reads as fresh.
newest_mtime() {
  local m
  m=$( { find "$1" -type f -exec stat -c %Y {} + 2>/dev/null || find "$1" -type f -exec stat -f %m {} + 2>/dev/null; } | sort -n | tail -n 1)
  printf '%s' "${m:-$NOW}"
}
if [ -d "$EPICO_DIR/stories" ]; then
  for S in "$EPICO_DIR"/stories/*/; do
    [ -d "$S" ] || continue
    S=${S%/}
    N=".epico/stories/$(basename "$S")"
    TASKS="$S/tasks.md"
    SCALE=$(front "$TASKS" scale)
    STATUS=$(front "$TASKS" status)

    BOXES=0
    [ -f "$TASKS" ] && BOXES=$(grep -cE '^[[:space:]]*- \[[ x~]\]' "$TASKS" || true)
    if [ "$BOXES" -eq 0 ]; then
      AGE_D=$(( (NOW - $(newest_mtime "$S")) / 86400 ))
      if [ "$AGE_D" -ge "$STALE_DAYS" ]; then
        add warning dormant "$N" "no boxes and untouched for $AGE_D days — resume it or remove it"
      elif [ ! -f "$TASKS" ] && [ ! -f "$S/.draft/meta.yaml" ]; then
        add error tasks "$N" "no tasks.md"
      fi
    fi

    case "$SCALE" in
      standard | full)
        [ -f "$S/story.md" ] || add error story "$N" "scale '$SCALE' but no story.md"
        ;;
    esac

    [ -d "$S/.draft/red-scratch" ] && add warning red-scratch "$N" "leftover .draft/red-scratch/ — Red scratch belongs under ${TMPDIR:-/tmp}/epic-red/, safe to delete"

    LOG="$S/.draft/progress.log"
    if [ "$STATUS" = "in-progress" ] && [ -s "$LOG" ]; then
      LAST=$(tail -n 1 "$LOG")
      T_AT=$(printf '%s' "$LAST" | jq -r '.at | fromdateiso8601' 2>/dev/null || true)
      if [[ "$T_AT" =~ ^[0-9]+$ ]]; then
        AGE=$(( (NOW - T_AT) / 60 ))
        if [ "$AGE" -ge "$STALL_MIN" ]; then
          WHERE=$(printf '%s' "$LAST" | jq -r '"task \(.task), step \(.step) (\(.status))"' 2>/dev/null || echo "unknown step")
          add warning stall "$N" "in progress, last progress note ${AGE} min ago at $WHERE"
        fi
      fi
    fi
  done
fi

# --- Worktrees: an untracked .epico/ copy diverges from the main tree's ---
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  MAIN=$(git -C "$ROOT" rev-parse --show-toplevel)
  while IFS= read -r line; do
    WT=${line#worktree }
    [ "$WT" = "$MAIN" ] && continue
    if [ -d "$WT/.epico" ] && [ -z "$(git -C "$WT" ls-files -- .epico 2>/dev/null | head -n 1)" ]; then
      add warning worktree-copy "$WT/.epico" "untracked .epico/ copy inside a worktree — the main tree's is the one modes read"
    fi
  done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep '^worktree ' || true)
fi

# --- Report ---
if [ ${#FINDINGS[@]} -eq 0 ]; then
  JSON=$(jq -n --arg e "$EPICO_DIR" '{epico_dir: $e, status: "ok", errors: 0, warnings: 0, findings: []}')
else
  JSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -s --arg e "$EPICO_DIR" '{
    epico_dir: $e,
    status: (if any(.severity == "error") then "error" else "warning" end),
    errors: (map(select(.severity == "error")) | length),
    warnings: (map(select(.severity == "warning")) | length),
    findings: .}')
fi

if $SUMMARY; then
  printf '%s' "$JSON" | jq -r 'select(.findings | length > 0)
    | "epico-doctor: \(.errors) error(s), \(.warnings) warning(s) — "
      + ([.findings[] | "\(.target): \(.detail)"] | .[:3] | join("; "))
      + (if (.findings | length) > 3 then "; … run epico-doctor for all \(.findings | length)" else "" end)'
else
  printf '%s\n' "$JSON"
fi
exit 0
