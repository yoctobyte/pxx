#!/bin/sh
# Print one hash over EVERY source the self-host fixedpoint is a fixedpoint of.
#
# WHY A SCRIPT AND NOT A MAKE EXPRESSION. The expression has to name 210 files,
# and a recipe that inlines $(COMPILER_SRC) $(COMPILER_INC) is echoed verbatim
# by `make -n` -- three times over, ~45KB, into the dry-run output that
# testmgr's make_dry_run() parses and that every agent reads. The Makefile
# already carries a note about exactly this trap ("it would print a
# $(COMPILER_INC) expansion that runs to 200 file names").
#
# THE COST OF THE SCRIPT IS A SECOND STATEMENT OF THE FILE SET, and that is the
# defect this whole change is about. It is DECLARED, and
# tools/selfhost_stamp_devtest.sh asserts the two lists are identical in both
# directions -- a file the Makefile compiles and this misses, or the reverse,
# fails there. One declared duplicate with a check is a different animal from
# an undeclared copy that nothing compares.
#
# The hash is per-file sha256 hashed as a SET (sorted), so it covers file NAMES
# as well as contents -- adding or deleting an .inc changes it -- and does not
# depend on the order a glob expands.
# bug-a-the-mandatory-fixedpoint-step-reports-success-from-a-stale-stamp
#
# POSIX sh, NOT bash, and that is load-bearing rather than tidiness. This was
# `#!/usr/bin/env bash` using ${BASH_SOURCE[0]}, and on a system without bash
# -- an Alpine/musl container, a BusyBox userland, any minimal image -- it did
# not run at all. `env: can't execute 'bash'` is printed, make CARRIES ON, and
# the stamp is written with an EMPTY srchash and srccount 0. The guard in
# $(COMPILER)'s recipe then compares the live hash (empty, same reason) against
# the stamp's (empty) and they MATCH, so the check that exists to refuse a
# stale stamp passes vacuously and prints "sources match it".
#
# Measured 2026-09-06 in `podman run alpine` with only git and make installed:
# modified compiler/compiler.pas, re-ran make, and got
#   "self-host fixedpoint: verified -- 1 round(s), 67075a6033c8 (stamp read
#    back; sources match it)"
# on sources the stamp had never seen. That is exactly the failure 01dd27dd1
# added the guard to make impossible, restored by the interpreter being absent.
#
# So: no bashisms here. $0 rather than ${BASH_SOURCE[0]} (this script is always
# invoked as a command, never sourced), and `set -u` without `-o pipefail`,
# which dash rejects outright. The pipeline's failure mode is covered instead by
# the recipe REFUSING an empty hash -- see the same commit -- because an empty
# result means "could not measure", never "measured and they match".
set -u
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

if [ "${1:-}" = "--list" ]; then
  # the devtest's half of the contract: print the set, one per line, sorted
  printf '%s\n' compiler/compiler.pas compiler/*.inc compiler/builtin/*.pas \
                lib/rtl/*.pas lib/asmcore/*.pas | sort
  exit 0
fi

if [ "${1:-}" = "--diagnose" ]; then
  # Explain a srchash mismatch. Takes the stamp's srccount ("" for a legacy
  # stamp that predates the field) and says WHICH WAY the sets differ, because
  # the two causes have two different repairs and the bare pair of 64-char
  # hashes above cannot tell them apart.
  #
  # THIS LIVES IN THE SCRIPT AND NOT IN THE RECIPE, for the reason at the top of
  # this file: `make -n` echoes recipes verbatim into the dry-run output that
  # testmgr's make_dry_run() parses. The first cut of this diagnostic put ~17
  # lines and a recursive $(MAKE) into the $(COMPILER) recipe and turned
  # `testmgr --tier quick` RED with a shell syntax error -- the same trap this
  # header was written about, one target down.
  stampn="${2:-}"
  liven=$("$0" --list | wc -l | tr -d ' ')
  if [ -n "$stampn" ] && [ "$stampn" != "$liven" ]; then
    echo "  THE FILE SET CHANGED, not just its contents: stamp $stampn files, tree $liven."
    echo "  A file was ADDED TO or REMOVED FROM the hashed set. The set is five"
    echo "  globs -- compiler/compiler.pas, compiler/*.inc, compiler/builtin/*.pas,"
    echo "  lib/rtl/*.pas, lib/asmcore/*.pas -- so an untracked stray dropped into"
    echo "  any of them counts as a source."
  elif [ -n "$stampn" ]; then
    echo "  Same $liven files on both sides, so a hashed file's CONTENTS changed."
  else
    echo "  Stamp predates the srccount field, so set-vs-contents cannot be told apart."
    echo "  It will be after the next rebuild."
  fi
  dirty=$(git status --porcelain --untracked-files=all -- \
            compiler lib/rtl lib/asmcore 2>/dev/null | grep -E '\.(inc|pas)$' || true)
  if [ -n "$dirty" ]; then
    echo "  Untracked or modified files in the hashed set, the likely cause:"
    printf '%s\n' "$dirty" | sed 's/^/    /' | head -20
  else
    # An EMPTY list is the informative case, so it is stated. A bare "suspects:"
    # header with nothing under it reads as a broken diagnostic.
    echo "  Nothing untracked or modified locally, so no stray file explains it:"
    echo "  this stamp was written for a DIFFERENT TREE. Usual cause is a pull"
    echo "  -- or a sync, which pulls -- with no rebuild after it."
  fi
  exit 0
fi

"$0" --list | tr '\n' '\0' | xargs -0 sha256sum | sort | sha256sum | cut -d' ' -f1
