#!/usr/bin/env bats
# scripts/check-reuse.sh: the fingerprint works on a COPY of the real index, and
# the copy must keep the real index's modification time.
#
# Git trusts a file's recorded stat (size and mtime, in seconds) unless the entry
# is "racily clean": its mtime is not older than the index file's own mtime, in
# which case git compares the content. A copy that gets a fresh mtime turns that
# protection off, so an edit of the same size made in the same second as the last
# index write goes unseen and a stale fingerprint says "the code did not change"
# — a false green for any reuse built on it. The times below are fixed, so the
# case does not depend on the clock.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/lib/reuse-fixture.sh
  source "$BATS_TEST_DIRNAME/lib/reuse-fixture.sh"
  reuse_setup
}

teardown() { reuse_teardown; }

@test "a same-size edit in the second the index was written is a code change" {
  # The entry records an mtime that is not older than the index file's own.
  touch -t 202601010001.00 src/app.sh
  git update-index --really-refresh
  touch -t 202601010000.00 "$PROJ/.git/index"
  f1=$(fp_now)
  is_hash "$f1"

  printf 'echo two\n' > src/app.sh
  touch -t 202601010001.00 src/app.sh
  # Sanity: git itself, reading the real index, sees the edit.
  if git --no-optional-locks diff --quiet -- src/app.sh; then
    echo "git does not see the edit: the case has not set the race up"
    return 1
  fi
  f2=$(fp_now)
  is_hash "$f2"
  [ "$f1" != "$f2" ]
}

@test "the fingerprint leaves the real index file's mtime alone" {
  touch -t 202601010000.00 "$PROJ/.git/index"
  before=$(stat -c %Y "$PROJ/.git/index" 2>/dev/null || stat -f %m "$PROJ/.git/index")
  fp_now >/dev/null
  after=$(stat -c %Y "$PROJ/.git/index" 2>/dev/null || stat -f %m "$PROJ/.git/index")
  [ "$before" = "$after" ]
}
