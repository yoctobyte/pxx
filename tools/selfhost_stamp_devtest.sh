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

# --- 5b. ...and the stamp's validity is tied to the SOURCES, not to mtimes ---
# The second face of the same bug, found in the wild three times in one day and
# reproduced deliberately twice: a binary and a stamp that AGREE WITH EACH OTHER
# but describe sources that are no longer on disk. The sha guard in step 4
# cannot fire (the pair is internally consistent) and the stamp's mtime is newer
# than the sources, so the loop never runs and the step prints a success line
# having proved nothing. mtime answers "was this written after the sources were
# touched"; the question is "was this written FOR these sources".
#
# What lands is a LOUD STOP, not an automatic rebuild -- see the Makefile note
# on why no witness file is used. So this row asserts the refusal.
#
# Planted rather than reasoned about, and planted in the LEGACY shape (a stamp
# with no srchash line), because that is what every existing checkout has on the
# day this lands: it is the arm that must work first.
#
# This one has to RUN make rather than use -n, since the check lives in the
# recipe. It is still cheap: the refusal happens before anything is compiled.
restore
if [ -f "$STAMP" ] && [ -x compiler/pascal26 ]; then
  cp "$STAMP" "$BAK.src5b"
  printf 'rounds 2\nsha256 %s\n' "$(sha256sum compiler/pascal26 | cut -d' ' -f1)" > "$STAMP"
  touch compiler/pascal26 "$STAMP"
  out=$(make compiler/pascal26 2>&1)
  case "$out" in *"written for DIFFERENT SOURCES"*) r=yes;; *) r=no;; esac
  check "a stamp written for OTHER sources is refused, not read back as success" "$r" "yes"
  case "$out" in *"self-host fixedpoint: verified"*) r=yes;; *) r=no;; esac
  check "...and it does NOT also print the success line" "$r" "no"
  cp "$BAK.src5b" "$STAMP"; rm -f "$BAK.src5b"
else
  echo "  SKIP source-hash arm -- need both a stamp and a binary"
fi

# --- 5c. the positive control on 5b: an HONEST stamp must still pass ---------
# Without this row, 5b passes for a check that refuses unconditionally, which
# would break every build in the repo and would look exactly like a guard.
restore
if [ -f "$STAMP" ]; then
  touch compiler/pascal26
  out=$(make compiler/pascal26 2>&1)
  case "$out" in *"self-host fixedpoint: verified"*) r=yes;; *) r=no;; esac
  check "an honest stamp for the CURRENT sources still verifies" "$r" "yes"
  case "$out" in *"written for DIFFERENT SOURCES"*) r=yes;; *) r=no;; esac
  check "...and is not refused" "$r" "no"
fi

# --- 5cc. the mismatch says WHICH WAY it differs, and both arms must fire ----
# A srchash mismatch has two causes with two different repairs, and the message
# used to print the same two opaque hashes for both. `srccount` separates them:
# a different FILE COUNT means the set changed (a stray .inc/.pas dropped into
# one of the five globs counts as a source), an equal count means a hashed
# file's CONTENTS changed. Both arms are asserted because a diagnostic that
# always picks one branch is the same animal as a guard that cannot fail.
#
# The legacy arm matters too: a stamp with no srccount line -- which is what
# every checkout has until its next rebuild -- must fall through to the plain
# message and say NEITHER, rather than claiming a set change from an empty
# count. That is 5b above, which plants exactly that shape.
restore
if [ -f "$STAMP" ] && [ -x compiler/pascal26 ]; then
  cp "$STAMP" "$BAK.src5cc"
  live_n=$(tools/compiler_srchash.sh --list | wc -l | tr -d ' ')
  bin_sha=$(sha256sum compiler/pascal26 | cut -d' ' -f1)

  printf 'rounds 1\nsha256 %s\nsrchash deadbeef\nsrccount %s\n' "$bin_sha" "$((live_n - 1))" > "$STAMP"
  touch compiler/pascal26 "$STAMP"
  out=$(make compiler/pascal26 2>&1)
  case "$out" in *"THE FILE SET CHANGED"*) r=yes;; *) r=no;; esac
  check "a DIFFERENT file count is reported as a set change" "$r" "yes"

  printf 'rounds 1\nsha256 %s\nsrchash deadbeef\nsrccount %s\n' "$bin_sha" "$live_n" > "$STAMP"
  touch compiler/pascal26 "$STAMP"
  out=$(make compiler/pascal26 2>&1)
  case "$out" in *"CONTENTS changed"*) r=yes;; *) r=no;; esac
  check "an EQUAL file count is reported as a contents change" "$r" "yes"
  case "$out" in *"THE FILE SET CHANGED"*) r=yes;; *) r=no;; esac
  check "...and does NOT also claim the set changed" "$r" "no"

  printf 'rounds 1\nsha256 %s\nsrchash deadbeef\n' "$bin_sha" > "$STAMP"
  touch compiler/pascal26 "$STAMP"
  out=$(make compiler/pascal26 2>&1)
  case "$out" in *"predates the srccount field"*) r=yes;; *) r=no;; esac
  check "a legacy stamp says it cannot tell set from contents" "$r" "yes"

  cp "$BAK.src5cc" "$STAMP"; rm -f "$BAK.src5cc"
else
  echo "  SKIP srccount arm -- need both a stamp and a binary"
fi

# --- 5ce. the $(COMPILER) recipe stays SHORT, because make -n is parsed -------
# tools/compiler_srchash.sh's header says why the file set is a script and not a
# make expression: `make -n` echoes recipes verbatim into the dry-run output
# that testmgr's make_dry_run() parses. That applies to ANY growth of this
# recipe, not only to inlining the file list -- measured 2026-09-06, when a
# 17-line diagnostic plus a recursive $(MAKE) in this recipe took the dry run
# from 24 lines to 75 and turned `testmgr --tier quick` RED with a shell syntax
# error. The repair was to move the logic into the script, where it costs the
# dry run one line. This row is the tripwire that was missing.
restore
dryn=$(make -n compiler/pascal26 2>/dev/null | wc -l | tr -d ' ')
if [ "$dryn" -le 40 ]; then r=yes; else r=no; fi
check "the compiler recipe's dry run stays small (${dryn} lines, cap 40)" "$r" "yes"
case "$(make -n compiler/pascal26 2>/dev/null)" in
  *'$(MAKE)'*|*"make --no-print-directory"*) r=yes;; *) r=no;;
esac
check "...and invokes no recursive make, which -n executes for real" "$r" "no"

# --- 5d. the two statements of the source set agree, in both directions -----
# tools/compiler_srchash.sh names the file set a second time, because inlining
# make's own $(COMPILER_SRC) $(COMPILER_INC) into a recipe put ~45KB of file
# names into every `make -n`. That duplicate is deliberate and this is the
# check that makes it safe: a file make compiles and the script misses would
# leave the hash blind to it (a real change reading as "sources match"), and a
# file the script hashes and make does not compile would force pointless
# rebuilds. Both directions, because a subset check passes in one of them.
# LC_ALL=C on BOTH sides and on comm. Without it comm printed "input is not in
# sorted order" and still reported ok -- sort's locale collation and comm's
# byte comparison disagree on '/' and '_', so the rows were passing while comm
# was telling us it could not answer.
mk_list=$(make --no-print-directory print-compiler-sources 2>/dev/null | LC_ALL=C sort -u)
sh_list=$(tools/compiler_srchash.sh --list 2>/dev/null | LC_ALL=C sort -u)
if [ -n "$mk_list" ] && [ -n "$sh_list" ]; then
  only_mk=$(LC_ALL=C comm -23 <(printf '%s\n' "$mk_list") <(printf '%s\n' "$sh_list"))
  only_sh=$(LC_ALL=C comm -13 <(printf '%s\n' "$mk_list") <(printf '%s\n' "$sh_list"))
  [ -z "$only_mk" ] && r=yes || r=no
  check "every source make names is hashed by compiler_srchash.sh${only_mk:+ (missing: $(printf '%s' "$only_mk" | tr '\n' ' '))}" "$r" "yes"
  [ -z "$only_sh" ] && r=yes || r=no
  check "every source compiler_srchash.sh hashes is one make names${only_sh:+ (extra: $(printf '%s' "$only_sh" | tr '\n' ' '))}" "$r" "yes"
else
  echo "  SKIP source-set agreement -- could not read one of the two lists"
  fails=$((fails+1))
fi

# --- 5d. AN UNMEASURABLE SOURCE HASH MUST REFUSE, NOT COMPARE EQUAL ----------
# The guard in $(COMPILER)'s recipe compares the live source hash against the
# stamp's. If compiler_srchash.sh cannot run, BOTH sides are empty and they
# MATCH -- so the check that exists to refuse a stale stamp passes vacuously and
# prints "sources match it" for a tree it never saw.
#
# That was not hypothetical. compiler_srchash.sh was `#!/usr/bin/env bash` using
# ${BASH_SOURCE[0]}, and measured 2026-09-06 in `podman run alpine` with only
# git and make: `env: can't execute 'bash'`, make carried on, the stamp was
# written with an empty srchash and srccount 0, and a MODIFIED compiler.pas
# still produced "verified -- sources match it". The script is POSIX sh now, and
# this row is the control that keeps it that way: it plants a script that runs
# and prints nothing, which is exactly the shape a missing interpreter produced.
restore
if [ -f "$STAMP" ] && [ -x compiler/pascal26 ]; then
  cp "$STAMP" "$BAK.src5d"
  cp tools/compiler_srchash.sh "$BAK.script5d"
  printf '#!/bin/sh\nexit 0\n' > tools/compiler_srchash.sh
  chmod +x tools/compiler_srchash.sh
  touch compiler/pascal26 "$STAMP"
  out=$(make compiler/pascal26 2>&1)
  rc=$?
  cp "$BAK.script5d" tools/compiler_srchash.sh
  chmod +x tools/compiler_srchash.sh
  cp "$BAK.src5d" "$STAMP"
  rm -f "$BAK.script5d" "$BAK.src5d"

  case "$out" in *"produced NO source hash"*) r=yes;; *) r=no;; esac
  check "an unmeasurable source hash is refused, not compared equal" "$r" "yes"

  if [ "$rc" -ne 0 ]; then r=yes; else r=no; fi
  check "...and the refusal is a nonzero exit, not just a message" "$r" "yes"

  # Match the SUCCESS LINE, not the phrase. The refusal message itself quotes
  # "sources match it" while explaining what used to go wrong, so a substring
  # test for that phrase matches the guard's own prose and fails on a correct
  # refusal -- which is exactly what it did when this row was first written.
  case "$out" in *"self-host fixedpoint: verified"*) r=yes;; *) r=no;; esac
  check "...and it does NOT print the success line" "$r" "no"
fi

# --- 6. the stamp is a build artifact, not a tracked file --------------------
if git check-ignore -q "$STAMP" 2>/dev/null; then r=yes; else r=no; fi
check "the stamp is gitignored" "$r" "yes"

echo
if [ "$fails" -ne 0 ]; then
  echo "selfhost-stamp-devtest: $fails FAILURE(S)"
  exit 1
fi
echo "selfhost-stamp-devtest: ALL OK"
