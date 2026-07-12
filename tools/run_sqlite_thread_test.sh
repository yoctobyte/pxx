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
SCALE="${TESTMGR_TIME_SCALE:-1}"
scaled() { awk -v t="$1" -v s="$SCALE" 'BEGIN { printf "%d", (t*s < t ? t : t*s) }'; }

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
run_to="$(scaled "$run_to")"
if [ -n "$qemu" ]; then
  got="$(timeout "$run_to" tools/run_target.sh "${ARCH}" "$bin")"
else
  got="$(timeout "$run_to" "$bin")"
fi
if [ "$got" = "$want" ]; then
  echo "test-sqlite-threads: PASS $ARCH (libc-free, shared+per-thread)"
else
  echo "test-sqlite-threads: FAIL $ARCH (output mismatch)"; exit 1
fi
