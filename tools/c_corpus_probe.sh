#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Whole-PROGRAM C differential against gcc, in a couple of minutes, without the
# full suite.
#
# WHY this exists, and it is a structural hole rather than a missing nicety.
# A Track C agent that changes something C-wide -- the token stream, the
# preprocessor, the struct member parser -- cannot run `make test-zlib` /
# `test-lua` / `test-quickjs`: .claude/hooks/no-full-suite.sh refuses them, and
# correctly, because they cost ten minutes and Track T sweeps them against the
# pushed sha anyway. So the agent's evidence is whatever small tests it wrote,
# and then a push and a hope. Two lanes fell into that in one night.
#
# WHY NOT gcc_diff_probe.sh: that harness answers "does this CALL agree with the
# oracle" over hundreds of small cases, and it is the right tool for that. This
# one answers "do substantial PROGRAMS still build, run and agree" -- a
# different question, and the one a C-wide change actually raises. Neither
# replaces the other and neither replaces Track T's corpora.
#
# THE ORACLE IS gcc. A program gcc cannot build proves nothing, so that is a
# SKIP -- counted, printed, and named. A silent skip is how a disarmed case sits
# for months looking like coverage.
#
# CORPUS. test/ccorpus/*.c ships with the repo and is self-contained: no
# third-party source is vendored (gate.sh asserts none is tracked). Real
# single-file libraries -- stb, cJSON, miniz -- are picked up from
# $PXX_C_CORPUS_DIR when the operator has fetched them, and the absence of that
# directory is reported with the path, exactly as `make test-lua` reports a
# missing lua tree rather than passing vacuously.
#
# THE LAST LINE IS A POSITIVE TOKEN THE PROBE ITSELF EMITS, not a status for the
# caller to interpret. A status can be produced by something other than the
# subject -- a `;`-list's last command, a pipe's right-hand side, a shell that
# never ran the probe at all -- and every one of those looks like success. If
# you do not see C-CORPUS-PROBE-COMPLETE, you did not get a result, whatever the
# exit code says.
#
# usage: tools/c_corpus_probe.sh [--pinned] [--keep] [pattern]
#   --pinned   use stable_linux_amd64/default/pinned instead of compiler/pascal26
#   --keep     leave the build directory in place and print it
#   pattern    only programs whose basename contains this substring

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PXX="$ROOT/compiler/pascal26"
KEEP=0
PATTERN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pinned) PXX="$ROOT/stable_linux_amd64/default/pinned" ;;
    --keep)   KEEP=1 ;;
    -h|--help) sed -n '1,45p' "$0"; exit 0 ;;
    *)        PATTERN="$1" ;;
  esac
  shift
done

if [ ! -x "$PXX" ]; then
  echo "c-corpus: no compiler at $PXX — run make compiler/pascal26 first"
  exit 2
fi
if ! command -v gcc >/dev/null 2>&1; then
  echo "c-corpus: gcc not on PATH, and gcc IS the oracle here — nothing to compare against"
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pxx-ccorpus-XXXXXX")"
cleanup() { [ "$KEEP" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT

SRCS=""
for f in "$ROOT"/test/ccorpus/*.c; do
  [ -e "$f" ] || continue
  SRCS="$SRCS $f"
done

EXTRA_DIR="${PXX_C_CORPUS_DIR:-}"
if [ -n "$EXTRA_DIR" ] && [ -d "$EXTRA_DIR" ]; then
  for f in "$EXTRA_DIR"/*.c; do
    [ -e "$f" ] || continue
    SRCS="$SRCS $f"
  done
else
  echo "c-corpus: NOTE no external corpus — set PXX_C_CORPUS_DIR to a directory of"
  echo "c-corpus:      single-file C programs (stb / cJSON / miniz) to widen this."
fi

echo "c-corpus: compiler $(sha256sum "$PXX" | cut -c1-12)  oracle $(gcc -dumpversion)"

n=0; same=0; skipped=0; failed=0
for src in $SRCS; do
  base="$(basename "$src" .c)"
  if [ -n "$PATTERN" ]; then
    case "$base" in *"$PATTERN"*) ;; *) continue ;; esac
  fi
  n=$((n + 1))

  if ! gcc -std=c99 -w -o "$WORK/$base.gcc" "$src" -lm > "$WORK/$base.gccbuild" 2>&1; then
    skipped=$((skipped + 1))
    echo "  SKIP  $base — the ORACLE cannot build it; this proves nothing about pxx"
    sed -n '1,3p' "$WORK/$base.gccbuild" | sed 's/^/        /'
    continue
  fi
  "$WORK/$base.gcc" > "$WORK/$base.gcc.out" 2>&1
  grc=$?

  if ! "$PXX" "$src" "$WORK/$base.pxx" > "$WORK/$base.pxxbuild" 2>&1; then
    failed=$((failed + 1))
    echo "  FAIL  $base — pxx could not build a program gcc builds"
    sed -n '1,4p' "$WORK/$base.pxxbuild" | sed 's/^/        /'
    continue
  fi
  "$WORK/$base.pxx" > "$WORK/$base.pxx.out" 2>&1
  prc=$?

  if [ "$grc" != "$prc" ]; then
    failed=$((failed + 1))
    echo "  FAIL  $base — exit code $prc, gcc says $grc"
    continue
  fi
  if cmp -s "$WORK/$base.gcc.out" "$WORK/$base.pxx.out"; then
    same=$((same + 1))
    echo "  SAME  $base  (rc=$grc)"
  else
    failed=$((failed + 1))
    echo "  DIFF  $base — output differs from the oracle"
    diff "$WORK/$base.gcc.out" "$WORK/$base.pxx.out" | sed -n '1,12p' | sed 's/^/        /'
  fi
done

[ "$KEEP" = "1" ] && echo "c-corpus: build tree kept at $WORK"

echo "C-CORPUS-PROBE-COMPLETE programs=$n identical=$same skipped=$skipped failed=$failed"
[ "$failed" = "0" ] || exit 1
exit 0
