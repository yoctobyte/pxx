#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# selfhost_fixedpoint.sh — the self-host gate, as a TEST rather than a build step.
#
# Byte-identical self-host is the most important property this project has, and
# until now it was asserted only inside the `make compiler/pascal26` rule. That
# means a BROKEN GATE LOOKED LIKE A BROKEN BOX: make failed, testmgr exited
# rc=1, and the watcher recorded "no report — infra problem, not recording a
# verdict". The gate failed silently, which is the one thing a gate must never
# do. (borg log: 1445 such deaths.) So it lives here now: a job, which can be
# RED, bisected to a culprit, and ticketed like any other failure.
#
# Two properties, and they are NOT the same:
#
#   1. CONVERGENCE (the gate).  Starting from the committed pinned stable, the
#      compiler built from these sources must eventually reproduce itself
#      byte-for-byte:  exists n <= MAX_ROUNDS:  stage_n == stage_{n+1}.
#      Note it is NOT "one pass from whatever seed you had". A stale seed
#      legitimately needs an extra round (stage2 came from the OLD compiler,
#      stage3 from the new one) — demanding one pass is what made a normal
#      bootstrap look like a failure.
#
#   2. AGREEMENT (the anti-Thompson check).  The fixedpoint reached from the
#      PINNED seed must equal the compiler testmgr actually built from the local
#      seed. A compiler can converge to a DIFFERENT self-reproducing fixedpoint
#      depending on which binary it started from — both stable, both "green",
#      one of them carrying whatever the local binary carried. That is the
#      Thompson trap, and only a hermetic seed can see it.
#
# Seeding from `pinned` (committed, known, identical on every box) is what makes
# this deterministic. Seeding from local disk state would make the answer depend
# on the machine, which is not a gate, it is a coin flip.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED="${PXX_STABLE:-$ROOT/stable_linux_amd64/default/pinned}"
SRC="$ROOT/compiler/compiler.pas"
BUILT="$ROOT/compiler/pascal26"
MAX_ROUNDS=4
T="${TESTMGR_TMP:-/tmp}/selfhost-fp-$$"
mkdir -p "$T" || exit 1
trap 'rm -rf "$T"' EXIT

test -x "$PINNED" || { echo "no pinned stable at $PINNED"; exit 77; }   # skip, not fail

cur="$PINNED"
for r in $(seq 1 $MAX_ROUNDS); do
  a="$T/stage_${r}a"; b="$T/stage_${r}b"
  "$cur" "$SRC" "$a" >/dev/null 2>&1 || { echo "FAIL: round $r — seed could not compile the compiler"; exit 1; }
  "$a"   "$SRC" "$b" >/dev/null 2>&1 || { echo "FAIL: round $r — stage could not compile the compiler"; exit 1; }
  if cmp -s "$a" "$b"; then
    echo "converged after $r round(s) from pinned: the compiler reproduces itself"
    # --- property 2: the hermetic fixedpoint must match what we actually test with
    if [ -x "$BUILT" ] && ! cmp -s "$a" "$BUILT"; then
      echo "FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26"
      echo "      (both may self-reproduce — that is exactly the point: two distinct"
      echo "       fixedpoints means the binary we test with is not the one these"
      echo "       sources define. Local seed contamination, or a self-perpetuating"
      echo "       miscompile.)"
      cmp "$a" "$BUILT" | head -2
      exit 1
    fi
    echo "agrees with compiler/pascal26 (the binary the suite is testing with)"
    exit 0
  fi
  cur="$a"
done
echo "FAIL: no fixedpoint after $MAX_ROUNDS rounds from pinned — the compiler"
echo "      built from these sources does not reproduce itself. This is a real"
echo "      self-host regression, not a stale seed."
exit 1
