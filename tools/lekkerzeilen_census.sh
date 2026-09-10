#!/bin/sh
# GOAL 4'S INSTRUMENT: compile every lekkerzeilen module with the NilPy frontend
# and report, per module, pass or the exact wall it hit.
#
# "have lekkerzeilen compile under nilpy as demo" (owner, 2026-09-10). This is
# how you find out where that stands, and it exists because the number was being
# produced by scratch scripts that nobody else could run -- so every report of it
# was a number with no reproduction beside it.
#
#   tools/lekkerzeilen_census.sh [--dir <tree>] [--quiet] [--module <file>]
#
# SKIPs (exit 0, loudly) when the tree is absent: lekkerzeilen is not vendored
# here, it is the owner's own project, and a missing corpus is not a red.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE RANKING ANYTHING ON THE OUTPUT.
#
# THIS IS A FIRST-FAILURE CENSUS AND THE WALL HISTOGRAM IS NOT A SIZE ESTIMATE.
# The compiler stops at the first error in a module, so every wall BEHIND the one
# reported is invisible, and the counts are biased in a direction this corpus has
# already demonstrated: imports sit at the top of a file, so an import wall is
# structurally over-represented as a first failure. Measured 2026-09-10 on this
# very corpus -- six import walls cleared across two passes moved
# modules-compiling by ZERO, because each module simply advanced to the next wall
# a few lines further down.
#
# So: a count of modules naming a blocker is a count of modules BLOCKED BY IT
# FIRST, never a count of the work it would deliver. Use it to find what to look
# at, and record what you expect a fix to move BEFORE you re-run -- a null row is
# only information to someone who said what they expected.
#
# `--threadsafe` IS PASSED UNCONDITIONALLY, and that is a measurement decision
# rather than a convenience. `import threading` is refused without it by design
# (the default heap, ARC and console I/O are not thread-safe), so without the
# flag every threading module walls on a diagnostic that is the compiler working
# correctly, and the census would report a feature as a defect.
# ---------------------------------------------------------------------------
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PXX="${PXX:-$ROOT/compiler/pascal26}"
LZ="${LZ_DIR:-/home/neo/lekkerzeilen}"
QUIET=0; ONE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)    LZ="$2"; shift 2 ;;
    --module) ONE="$2"; shift 2 ;;
    --quiet)  QUIET=1; shift ;;
    *) echo "lz-census: unknown argument $1" >&2; exit 2 ;;
  esac
done

[ -x "$PXX" ] || { echo "lz-census: no compiler at $PXX" >&2; exit 1; }
if [ ! -d "$LZ/lekkerzeilen" ]; then
  echo "lz-census: SKIP -- no lekkerzeilen tree at $LZ (set LZ_DIR= or --dir)"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lzcensus-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The compiler is identified in the output, every time. A census quoted without
# the binary that produced it cannot be compared with the next one, and this
# corpus moves under the fleet several times a day -- mimic_threading.pas landing
# turned one wall into a flag between two runs on 2026-09-10.
printf 'lz-census: compiler %s\n' "$(sha256sum "$PXX" | cut -c1-12)"
printf 'lz-census: tree     %s\n' "$(cd "$ROOT" && git log --format=%h -1)"
printf 'lz-census: corpus   %s\n' "$LZ"

if [ -n "$ONE" ]; then
  MODULES="$ONE"
else
  MODULES="$( cd "$LZ" && find lekkerzeilen -name '*.py' | sort )"
fi

NPASS=0; NFAIL=0
: > "$WORK/rows"
for m in $MODULES; do
  tag="$(printf '%s' "$m" | tr /. __ | sed 's/_py$//')"
  if ( cd "$LZ" && "$PXX" --threadsafe "$m" "$WORK/$tag" ) > "$WORK/$tag.log" 2>&1; then
    NPASS=$((NPASS+1))
    printf 'ok   %s\n' "$m" >> "$WORK/rows"
  else
    NFAIL=$((NFAIL+1))
    # THE FIRST *ERROR*, NOT THE FIRST DIAGNOSTIC -- and this script shipped the
    # wrong version of this line for exactly one run, which is how the defect was
    # found. Matching `^pascal26:` takes whichever diagnostic comes first, and the
    # compiler emits WARNINGS before the error that actually stopped it, so
    # __main__.py and traffic.py were both reported as walled on
    # "warning: no class declares a method or callable field" while their real
    # wall sat further down the log. A census that names a warning as a blocker
    # sends somebody to fix a non-problem, and nothing about the row looks wrong.
    # So: errors first, warnings only when there is no error to find.
    err="$(grep -m1 -E '(error|Error|Fatal):' "$WORK/$tag.log" || true)"
    [ -n "$err" ] || err="$(grep -m1 -E '^(pascal26|[A-Za-z0-9_]+\.(pas|inc)):' "$WORK/$tag.log" || true)"
    [ -n "$err" ] || err="(no diagnostic at all -- a segfault or a kill looks like this)"
    printf 'FAIL %s :: %s\n' "$m" "$err" >> "$WORK/rows"
  fi
done

# ---- cascade marking -------------------------------------------------------
# AN ERROR RAISED INSIDE AN IMPORTED MODULE PRINTS THAT MODULE'S LINE NUMBER AND
# NO FILE NAME, so the reader supplies the file they invoked and two subjects look
# like two defects. The tell is free and it is the line number: when two subjects
# report the SAME line with the SAME message, suspect one site reached through an
# import before believing a shared cause.
#
# Measured on this corpus 2026-09-10 -- atlas.py and world.py both say 188, and
# only world.py contains the construct; gauges.py and __main__.py both say 174,
# and __main__.py has none of it. Four sqlite3 rows, TWO sites. An earlier ticket
# ranked a one-site fix as gating two modules on exactly this reading, and
# frankB, who was compiling the modules one at a time, flagged it here before the
# number went anywhere.
#
# This marks the suspicion; it does not resolve it. Confirming means grepping the
# subject for the construct, which needs to know what the construct IS -- so the
# row says `cascade?` and names its partners, and the reader does the one grep.
mark_cascades() {
  while IFS= read -r row; do
    case "$row" in
      FAIL*)
        sig="${row#*:: }"
        n=$(grep -cF ":: $sig" "$WORK/rows" || true)
        if [ "${n:-0}" -gt 1 ]; then
          peers="$(grep -F ":: $sig" "$WORK/rows" | sed 's/^FAIL \([^ ]*\) .*/\1/' \
                   | grep -vxF "$(printf '%s' "$row" | sed 's/^FAIL \([^ ]*\) .*/\1/')" \
                   | tr '\n' ' ')"
          printf '%s\n      ^ cascade? %d subjects report this identical line; likely ONE site reached through an import (also: %s)\n' \
            "$row" "$n" "$peers"
        else
          printf '%s\n' "$row"
        fi ;;
      *) printf '%s\n' "$row" ;;
    esac
  done < "$WORK/rows"
}

[ "$QUIET" = 1 ] || mark_cascades | sed 's/^/  /'

echo
printf 'lz-census: %d of %d modules compile\n' "$NPASS" "$((NPASS+NFAIL))"

# The wall classes, by how many modules hit each FIRST -- see the caveat above.
if [ "$NFAIL" -gt 0 ]; then
  echo
  echo "lz-census: walls, by modules hitting each FIRST (NOT a count of work):"
  grep '^FAIL' "$WORK/rows" \
    | sed 's/^FAIL [^ ]* :: //; s/pascal26:[0-9]*: //; s/[0-9]\{2,\}/N/g' \
    | cut -c1-72 | sort | uniq -c | sort -rn | sed 's/^/  /'
fi
