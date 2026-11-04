#!/usr/bin/env bash
# PreToolUse hook: only `epico-check run` writes the reuse ledger.
#
# The ledger directory is <git-common-dir>/epico/reuse/ (see check-reuse.sh): a
# PASS recorded there must stand for a run that really happened. This guard
# denies
#   - Edit/Write whose file_path resolves inside that directory;
#   - a Bash command that names that directory together with a redirect into it,
#     or with cp / mv / tee / rm, whatever else it runs. There is no exemption
#     for a command that also calls epico-check: the runner writes the ledger
#     itself, never through the text of an agent's command, so
#     `cp forged.json <dir>/ledger.json && epico-check stats` is still denied.
# Residual, accepted: the Bash check is pattern-based, so an obfuscated write
# (a variable holding the path) can slip past it.
#
# It fails open: any error of its own (bad stdin, no git) lets the call through,
# because hooks.json registers it with onFailure "block" and the script itself
# is what keeps a session unblocked. Every exit is therefore 0; a deny is the
# JSON form of permissionDecision "deny".

set -euo pipefail
trap 'exit 0' EXIT

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
case "$TOOL" in
  Edit | Write | Bash) ;;
  *) exit 0 ;;
esac

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$PWD

# Same resolution as check-reuse.sh: --git-common-dir is relative (".git") in a
# main worktree and absolute in a linked one, so ask for the absolute form.
COMMON=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ -n "$COMMON" ] || exit 0

# canon <path> — absolute path with "." and ".." collapsed and every symlink
# resolved, including those of a parent that exists while the leaf does not.
canon() {
  local path=$1 cur="" comp target hops=0
  local -a queue=() tq=()
  IFS=/ read -ra queue <<< "$path"
  while [ "${#queue[@]}" -gt 0 ]; do
    comp=${queue[0]}
    queue=("${queue[@]:1}")
    case "$comp" in
      "" | .) continue ;;
      ..) cur=${cur%/*}; continue ;;
    esac
    cur="$cur/$comp"
    if [ -L "$cur" ]; then
      hops=$((hops + 1))
      [ "$hops" -le 40 ] || return 1
      target=$(readlink "$cur") || return 1
      cur=${cur%/*}
      [[ "$target" != /* ]] || cur=""
      tq=()
      IFS=/ read -ra tq <<< "$target"
      queue=("${tq[@]}" "${queue[@]}")
    fi
  done
  printf '%s' "${cur:-/}"
}

LEDGER=$(canon "$COMMON/epico/reuse") || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

RULE="The reuse ledger ($LEDGER) is written only by \`epico-check run\`: a PASS recorded there must stand for a run that happened. Run the check through epico-check instead of writing into that directory."

case "$TOOL" in
  Edit | Write)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -n "$FILE" ] || exit 0
    [[ "$FILE" == /* ]] || FILE="$CWD/$FILE"
    FILE=$(canon "$FILE") || exit 0
    case "$FILE" in
      "$LEDGER" | "$LEDGER"/*) deny "$RULE" ;;
    esac
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    [ -n "$CMD" ] || exit 0

    esc() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
    # The directory by its absolute path, or spelled from the common dir's own
    # name (".git" in a main worktree). A name must end at the directory: the
    # next character is not part of a longer name ("reuse-old", "reusex").
    DIR_ABS=$(esc "$LEDGER")
    DIR_REL="$(esc "${COMMON##*/}")/epico/reuse"
    END='([^A-Za-z0-9_.-]|$)'
    PATH_RE="(${DIR_ABS}|(^|[^A-Za-z0-9_-])${DIR_REL})${END}"

    # A redirect whose target is the directory: `>`, `>>`, `>|`, `2>`, with no
    # command separator between the operator and the path.
    REDIR_RE=">[^;&|<>]*${PATH_RE}"
    VERB_RE='(^|[;&|(`{/\\[:space:]])(cp|mv|tee|rm)([[:space:]]|$)'
    CD_RE='(^|[;&|(`{[:space:]])(cd|pushd)[[:space:]]'

    [[ "$CMD" =~ $PATH_RE ]] || exit 0
    if [[ "$CMD" =~ $REDIR_RE ]] || [[ "$CMD" =~ $VERB_RE ]]; then
      deny "$RULE"
    fi
    # `cd <dir> && echo x > ledger.json`: the path and the redirect are apart.
    if [[ "$CMD" =~ $CD_RE ]] && [[ "$CMD" == *">"* ]]; then
      deny "$RULE"
    fi
    ;;
esac
exit 0
