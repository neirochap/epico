#!/usr/bin/env bats
# scripts/check-reuse.sh (bin/epico-check): the code fingerprint, read through
# `lookup -- <command>`.
#
# The fingerprint names the code a check ran on: every tracked file and every
# untracked file git does not ignore, minus .epico/ and .epic/ — whichever way
# those are kept. It is computed on a copy of the index, so the real index is
# never touched. Where it cannot be computed — not a git work tree, a git
# failure, a submodule holding uncommitted content — it is null and `reason`
# says why. Usage errors exit 2 and print no JSON.
#
# Hostile halves first: a change that IS code must split the fingerprint, then
# a change that is NOT code must leave it whole, then the plain cases.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
}

teardown() { reuse_teardown; }

# --- Must differ: a code change is never read as the same code ---

@test "an edited tracked file changes the fingerprint" {
  a=$(fp_now)
  is_hash "$a"
  printf 'echo two\n' > src/app.sh
  b=$(fp_now)
  is_hash "$b"
  [ "$a" != "$b" ]
}

@test "a new untracked file git does not ignore changes the fingerprint" {
  a=$(fp_now)
  is_hash "$a"
  printf 'echo new\n' > src/new.sh
  b=$(fp_now)
  is_hash "$b"
  [ "$a" != "$b" ]
}

@test "a root file whose name only starts like .epico or .epic is code" {
  # The exclusion is the two directories, not every name sharing their prefix.
  a=$(fp_now)
  is_hash "$a"
  printf 'notes\n' > .epico-notes.md
  b=$(fp_now)
  [ "$a" != "$b" ]
  printf 'notes\n' > .epic.md
  c=$(fp_now)
  [ "$b" != "$c" ]
}

# --- Must stay equal: what is not code never splits the fingerprint ---

@test ".epico versioned: changing and adding files under it keeps the fingerprint" {
  mkdir -p .epico/stories/001-a .epic
  printf 'v1\n' > .epico/stories/001-a/tasks.md
  printf 'v1\n' > .epic/old.md
  git add -A && commit_all "track the story"
  a=$(fp_now)
  is_hash "$a"
  printf 'v2\n' > .epico/stories/001-a/tasks.md
  printf 'new\n' > .epico/stories/001-a/story.md
  printf 'v2\n' > .epic/old.md
  b=$(fp_now)
  [ "$a" = "$b" ]
}

@test ".epico gitignored: changing and adding files under it keeps the fingerprint" {
  printf '.epico/\n.epic/\n' >> .gitignore
  git add -A && commit_all "ignore the story tree"
  mkdir -p .epico/stories/001-a .epic
  printf 'v1\n' > .epico/stories/001-a/tasks.md
  a=$(fp_now)
  is_hash "$a"
  printf 'v2\n' > .epico/stories/001-a/tasks.md
  printf 'x\n' > .epico/reuse-profile.json
  printf 'x\n' > .epic/old.md
  b=$(fp_now)
  [ "$a" = "$b" ]
}

@test ".epico gitignored while holding a tracked file: changing that file keeps the fingerprint" {
  # git check-ignore calls such a directory not ignored; the fingerprint must
  # not depend on that answer.
  printf '.epico/\n' >> .gitignore
  mkdir -p .epico/archive/001-a
  printf 'v1\n' > .epico/archive/001-a/tasks.md
  git add .gitignore && git add -f .epico/archive/001-a/tasks.md && commit_all "an archived story kept tracked"
  a=$(fp_now)
  is_hash "$a"
  printf 'v2\n' > .epico/archive/001-a/tasks.md
  printf 'new\n' > .epico/archive/001-a/story.md
  b=$(fp_now)
  [ "$a" = "$b" ]
  rm .epico/archive/001-a/tasks.md
  c=$(fp_now)
  [ "$a" = "$c" ]
}

@test "a gitignored file that is not a profile input keeps the fingerprint" {
  a=$(fp_now)
  is_hash "$a"
  mkdir -p build
  printf 'log\n' > build/out.log
  printf 'SECRET=1\n' > .env
  b=$(fp_now)
  [ "$a" = "$b" ]
}

# --- The plain cases ---

@test "on a clean checkout the fingerprint is the commit's tree, and it is stable" {
  a=$(fp_now)
  [ "$a" = "$(git rev-parse 'HEAD^{tree}')" ]
  [ "$(fp_now)" = "$a" ]
}

@test "computing the fingerprint leaves the real index alone" {
  printf 'echo new\n' > src/new.sh
  printf 'echo two\n' > src/app.sh
  staged_before=$(git ls-files --stage | cksum)
  a=$(fp_now)
  is_hash "$a"
  [ "$(git ls-files --stage | cksum)" = "$staged_before" ]
  [ -z "$(git diff --cached --name-only)" ]
  [ "$(git ls-files --others --exclude-standard)" = "src/new.sh" ]
}

@test "lookup prints the JSON contract on one line" {
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  jq -e 'has("mode") and has("would_reuse") and has("fingerprint") and has("key") and has("last") and has("reason")' <<< "$output"
  jq -e '(.would_reuse | type) == "boolean"' <<< "$output"
  is_hash "$(jq -r .fingerprint <<< "$output")"
  is_hash "$(jq -r .key <<< "$output")"
}

# --- No fingerprint: run anyway, and say why ---

@test "a directory that is not a git work tree: fingerprint null, with a reason" {
  mkdir -p "$WORK/plain"
  cd "$WORK/plain"
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.fingerprint == null' <<< "$output"
  jq -e '(.reason | type) == "string" and (.reason | length) > 0' <<< "$output"
  [ ! -e "$WORK/plain/.git" ]
}

@test "a git failure (an unreadable file): fingerprint null, with a reason" {
  if [ "$(id -u)" -eq 0 ]; then skip "root reads a mode-000 file"; fi
  printf 'x\n' > src/locked.txt
  chmod 000 src/locked.txt
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.fingerprint == null' <<< "$output"
  jq -e '(.reason | length) > 0' <<< "$output"
}

@test "a submodule with uncommitted content: fingerprint null; the same submodule clean: a fingerprint" {
  git init -q "$WORK/sub"
  printf 'a\n' > "$WORK/sub/f.txt"
  git -C "$WORK/sub" add -A
  git -C "$WORK/sub" -c user.email=t@example.invalid -c user.name=t commit -q -m sub
  git -c protocol.file.allow=always submodule add -q "$WORK/sub" lib/sub
  commit_all "add the submodule"
  # The clean half first: a submodule alone is never a reason to refuse.
  clean=$(fp_now)
  is_hash "$clean"
  printf 'b\n' >> lib/sub/f.txt
  run --separate-stderr cr lookup -- "true"
  [ "$status" -eq 0 ]
  jq -e '.fingerprint == null' <<< "$output"
  jq -e '(.reason | length) > 0' <<< "$output"
}

# --- Usage and the wrapper ---

@test "usage errors exit 2 and print no JSON" {
  run --separate-stderr cr
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr frobnicate
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr lookup
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  run --separate-stderr cr lookup --
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "bin/epico-check runs scripts/check-reuse.sh and answers the same" {
  [ -x "$PLUGIN_ROOT/bin/epico-check" ]
  grep -qE '^exec bash "\$\(dirname "\$0"\)/\.\./scripts/check-reuse\.sh" "\$@"$' "$PLUGIN_ROOT/bin/epico-check"
  run --separate-stderr "$PLUGIN_ROOT/bin/epico-check" lookup -- "true"
  [ "$status" -eq 0 ]
  is_hash "$(jq -r .fingerprint <<< "$output")"
  [ "$(jq -r .fingerprint <<< "$output")" = "$(fp_now)" ]
}
