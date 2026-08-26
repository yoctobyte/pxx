#!/usr/bin/env bash
# Devtest: `make compiler/pascal26` cannot be satisfied by a file timestamp.
#
# CLAUDE.md calls that rule the one gate that cannot be skipped, because it IS
# the byte-identical self-host fixedpoint. It was skippable: in a tree whose
# seed arrived from OUTSIDE the build -- a pinned binary copied into a scratch
# worktree -- the binary is newer than every source, make declares the target up
# to date, the recipe never runs, and the gate exits 0 having proved nothing.
# The tell was not an error but a success message in the wrong dialect:
#   make: 'compiler/pascal26' is up to date.
# standing exactly where `converged after 1 round(s)` belonged. A full-tier
# sweep was about to report a verdict for one sha against a binary built from a
# pin 133 commits older.
# bug-a-the-selfhost-rule-is-a-no-op-when-the-seed-is-newer-than-its-sources
#
# Uses `make -n`, so it RUNS NOTHING: it asks make which recipe it would choose,
# which is precisely the question the bug got wrong. Whole thing is under a
# second and it never builds, never mutates a binary, and never races the
# watcher. The one file it touches is the stamp, moved aside and put back.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

STAMP=compiler/.pascal26.fixedpoint
fails=0

check() {   # $1=name $2=got $3=want
  if [ "$2" = "$3" ]; then printf '  ok  %s\n' "$1"
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

BAK=$(mktemp -u)
had_stamp=no
if [ -f "$STAMP" ]; then had_stamp=yes; cp "$STAMP" "$BAK"; fi
restore() {   # idempotent: step 3 calls it too, then the trap calls it again
  if [ "$had_stamp" = yes ] && [ -f "$BAK" ]; then cp "$BAK" "$STAMP"; fi
}
trap 'restore; rm -f "$BAK"' EXIT

# --- 1. the fixedpoint loop is the STAMP's work, not the binary's ------------
# With no stamp, make must plan to run the loop -- however new the binary is.
# This is the reported bug: before the fix the same state planned nothing.
rm -f "$STAMP"
touch compiler/pascal26 2>/dev/null
out=$(make -n compiler/pascal26 2>&1)
case "$out" in *"converged after"*) r=yes;; *) r=no;; esac
check "no stamp: the fixedpoint loop is planned even with a newer binary" "$r" "yes"

# --- 2. and the stamp is what records the proof ------------------------------
case "$out" in *"$STAMP"*) r=yes;; *) r=no;; esac
check "no stamp: the loop writes the stamp" "$r" "yes"

# --- 3. with a stamp, the VERIFY still runs ----------------------------------
# The second half of the same bug, and the first fix missed it: a stamp written
# last is newer than the binary, so "the recipe always runs" holds -- until
# something cp's over the binary, which makes it newer than the stamp again and
# the verify is skipped in the same silence. Only a PHONY prerequisite makes the
# check independent of every timestamp.
restore
[ -f "$STAMP" ] || { echo "  SKIP no stamp to test with -- run make compiler/pascal26 first"; exit 0; }
touch compiler/pascal26 2>/dev/null
out=$(make -n compiler/pascal26 2>&1)
case "$out" in *sha256sum*) r=yes;; *) r=no;; esac
check "stamp present, binary newer: the sha verify is still planned" "$r" "yes"

case "$out" in *"is up to date"*) r=yes;; *) r=no;; esac
check "stamp present: make does NOT answer 'is up to date'" "$r" "no"

# --- 4. the verify compares the binary against the RECORDED sha --------------
case "$out" in *"proves a fixedpoint for"*) r=yes;; *) r=no;; esac
check "the verify refuses a binary the stamp does not vouch for" "$r" "yes"

# --- 5. and it says which it is, so a pass and a skip are distinguishable ----
case "$out" in *"self-host fixedpoint: verified"*) r=yes;; *) r=no;; esac
check "the verify names its own provenance" "$r" "yes"

# --- 6. the stamp is a build artifact, not a tracked file --------------------
if git check-ignore -q "$STAMP" 2>/dev/null; then r=yes; else r=no; fi
check "the stamp is gitignored" "$r" "yes"

echo
if [ "$fails" -ne 0 ]; then
  echo "selfhost-stamp-devtest: $fails FAILURE(S)"
  exit 1
fi
echo "selfhost-stamp-devtest: ALL OK"
