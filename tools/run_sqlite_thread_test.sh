#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# One arch of the threadsafe-sqlite gate (extracted from the former monolithic
# test-sqlite-threads recipe so tools/testmgr.py can run the four arches in
# parallel; `make test-sqlite-threads` still runs all four, serially).
#
# Usage: tools/run_sqlite_thread_test.sh <x86_64|i386|aarch64|arm32> [compiler] [sqlite-src]
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCH="${1:?arch required: x86_64|i386|aarch64|arm32}"
CC="${2:-$ROOT/compiler/pascal26}"
SQLITE_SRC="${3:-$ROOT/library_candidates/sqlite}"
cd "$ROOT"

if [ ! -f "$SQLITE_SRC/sqlite3.c" ]; then
  echo "test-sqlite-threads: SKIP — no sqlite amalgamation at $SQLITE_SRC/sqlite3.c"
  exit 0
fi

want="$(printf 'shared OK\nperthread OK\nall OK')"

# Calibration: tools/testmgr.py exports TESTMGR_TIME_SCALE (probe-compile
# time vs reference box) so run timeouts stretch on weak hardware instead of
# false-failing. Serial make runs get the neutral default.
#
# TIME_SCALE ALONE IS NOT ENOUGH, and this runner was the last qemu one still
# using only it. It is an IDLE HARDWARE probe: it stays ~1.00 on a fast box, so
# it never captures "the box is busy", which is the condition a full sweep
# creates for itself. The other three qemu runners (run_c_conformance.sh,
# run_pascal_conformance.sh, run_fgl_corpus.sh) all multiply by
# TESTMGR_LOAD_SCALE = cap/cores as well, for exactly this failure --
# regression-testmgr-conformance-shard-timeout-under-load. Measured 2026-08-31
# on seven: this job died at its hardcoded 120s with TESTMGR_TIME_SCALE=1.00
# while a 592-second full tier ran around it. Seven is not slow; it is busy.
# (frankS built the diagnostic that could say so, fc5762a2f; frankA read it.)
SCALE="${TESTMGR_TIME_SCALE:-1}"
LOAD="${TESTMGR_LOAD_SCALE:-1}"

# THE CAP IS NOT TIMIDITY, IT IS A COLLISION THAT WAS EXACT. testmgr classes
# this job as `qemu`, whose OUTER per-job timeout is 240s (CLASSES in
# tools/testmgr.py). LOAD_SCALE is ~2.00 at default width (hard_cap = nproc*2),
# so the sibling formula alone gives 120 * 1.00 * 2.00 = 240 -- precisely the
# outer. The outer would then pre-empt the inner, and the job-level kill says
# only "TIMED OUT", discarding the elapsed/budget/scale line this runner exists
# to print. We would have spent the diagnostic to buy the budget.
# So: stretch, but stay strictly under the outer.
# tools/run_sqlite_inner_budget_devtest.py reads BOTH numbers -- this cap and
# testmgr's qemu class timeout -- and fails if the gap ever closes, so changing
# either one alone cannot silently recreate the collision.
INNER_CAP=200
scaled() {
  awk -v t="$1" -v s="$SCALE" -v l="$LOAD" -v cap="$INNER_CAP" \
      'BEGIN { v = t * s * l; if (v < t) v = t; if (v > cap) v = cap;
               printf "%d", v }'
}

case "$ARCH" in
  x86_64)  tgt="";              qemu="";             run_to=60 ;;
  i386)    tgt="--target=i386";    qemu="qemu-i386";    run_to=90 ;;
  aarch64) tgt="--target=aarch64"; qemu="qemu-aarch64"; run_to=120 ;;
  arm32)   tgt="--target=arm32";   qemu="qemu-arm";     run_to=150 ;;
  *) echo "unknown arch $ARCH"; exit 2 ;;
esac

if [ -n "$qemu" ] && ! command -v "$qemu" >/dev/null 2>&1; then
  echo "test-sqlite-threads: SKIP $ARCH ($qemu not installed)"
  exit 0
fi

# Private scratch: the old fixed /tmp/csqlite_thread_test26_$ARCH is shared by
# every checkout on the box, so two concurrent runs (dev tree + watcher clone)
# clobber each other's binary mid-build — seen as phantom "not libc-free" /
# output-mismatch reds. testmgr exports TESTMGR_TMP for exactly this.
tmpd="$(mktemp -d "${TESTMGR_TMP:-/tmp}/cstt_${ARCH}.XXXXXX")" || exit 2
trap 'rm -rf "$tmpd"' EXIT INT TERM
bin="$tmpd/csqlite_thread_test26_$ARCH"
err="$tmpd/cstt_$ARCH.err"
echo "test-sqlite-threads: building threadsafe sqlite ($ARCH) ..."
# shellcheck disable=SC2086 — $tgt is deliberately empty for x86_64
if ! "$CC" --threadsafe $tgt -Ilib/crtl/include -Ilib/crtl/src -I"$SQLITE_SRC" \
     test/csqlite_thread_test.c "$bin" 2>"$err"; then
  echo "test-sqlite-threads: FAIL $ARCH (build error)"; head -5 "$err"; exit 1
fi
if readelf -d "$bin" 2>/dev/null | grep -qi 'NEEDED'; then
  echo "test-sqlite-threads: FAIL $ARCH (not libc-free — has DT_NEEDED)"; exit 1
fi
# CSTT_RUN_TIMEOUT overrides the scaled budget. It exists so the TIMED OUT
# branch below can be EXERCISED -- `CSTT_RUN_TIMEOUT=5 tools/run_sqlite_thread_test.sh
# aarch64` must print TIMED OUT, and a branch nobody has ever seen fire is not
# a diagnostic, it is a guess written in the imperative.
run_to="${CSTT_RUN_TIMEOUT:-$(scaled "$run_to")}"
# A TIMEOUT AND A WRONG ANSWER USED TO PRINT THE SAME LINE. `timeout` kills the
# run, `got` comes back EMPTY, and the mismatch branch reported "output
# mismatch" -- so a job that is merely too slow on a loaded box was
# indistinguishable from a miscompile, and a red that sat untracked for three
# days could not be triaged from the report at all
# (regression-test-sqlite-threads-aarch64-output-mismatch-untracked-since-08-29).
# Measured on plexus: the aarch64 run takes ~37s of its 120s budget and
# `timeout 5` on the same binary gives rc=124 with empty output, which the old
# branch called a mismatch.
# So: keep the exit code, name the timeout, and PRINT WHAT WE GOT. The report
# quotes this text and nothing else, which is why the actual output has to be in
# it rather than in a variable nobody can see.
started="$(date +%s)"
if [ -n "$qemu" ]; then
  got="$(timeout "$run_to" tools/run_target.sh "${ARCH}" "$bin")"; rc=$?
else
  got="$(timeout "$run_to" "$bin")"; rc=$?
fi
elapsed="$(( $(date +%s) - started ))"
if [ "$got" = "$want" ]; then
  echo "test-sqlite-threads: PASS $ARCH (libc-free, shared+per-thread) ${elapsed}s/${run_to}s"
elif [ "$rc" = "124" ]; then
  echo "test-sqlite-threads: FAIL $ARCH (TIMED OUT after ${run_to}s; TESTMGR_TIME_SCALE=$SCALE TESTMGR_LOAD_SCALE=$LOAD cap=${INNER_CAP}s)"
  echo "  partial output: [$got]"
  exit 1
else
  echo "test-sqlite-threads: FAIL $ARCH (output mismatch, exit $rc, ${elapsed}s/${run_to}s)"
  echo "  want: [$(printf '%s' "$want" | tr '\n' '|')]"
  echo "  got:  [$(printf '%s' "$got" | tr '\n' '|')]"
  exit 1
fi
