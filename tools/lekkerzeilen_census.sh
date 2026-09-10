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
# A ROW IS A PROPERTY OF THE (MODULE, ENTRY POINT) PAIR, NOT OF THE MODULE.
# frankB measured this on capture.py 2026-09-11: compiled AS THE SUBJECT it walls
# at `:10 no unit named ctypes`; reached as a DEPENDENCY of __main__.py it walled
# at `:20 zlib.crc32` instead, because a bare `import ctypes` is fatal for a main
# program and evidently not for a module arriving as a dependency. Same file, same
# compiler, two different first walls, both correct.
#
# THIS CENSUS COMPILES EVERY MODULE AS A SUBJECT. So every row here is an
# as-subject row, and two consequences follow. Two censuses that disagree about a
# module may BOTH be right, so a diff between runs is not automatically a delta --
# check the entry point before calling it one. And clearing a wall reported here
# may not move that module when it is reached as a dependency, or the reverse.
# Making the entry point part of a row's identity is the fix; it is not built.
#
# AND THE WALL MESSAGE DEPENDS ON WHAT ELSE IS LINKED, so grouping by message text
# can split ONE construct across two buckets. frankZ measured it 2026-09-10 on
# `except (urllib.error.URLError, OSError, ValueError)`: with mimic_sqlite3 linked
# the qualifier's middle segment `error` RESOLVES, flat and case-insensitively, so
# the parser accepted `urllib.error` as a complete class and then met `.URLError`
# -- `expected ')' before '.'`. Without it nothing named `error` existed and it
# stopped a token earlier -- `unknown exception class error`. Two messages, one
# construct, and which one you get changes as the shim library grows. That is the
# same-line-number rule one level up, with the MESSAGE as the manufactured
# equivalence class instead of the line.
#
# A third form of it is the HOST: a bare NilPy import whose Pascal chain is closed
# falls through to the host's C headers, so `import zlib` on a box with zlib-dev
# installed reports `no overload of crc32 matches these arguments` (the C crc32 is
# 3-arg) where a box without it reports `no member crc32`. Measured 2026-09-11.
# A census compared across machines can see two walls for one cause.
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
# THE TREE SHA IS DERIVED FROM THE RESOLVED $PXX, NOT FROM THIS SCRIPT'S OWN
# LOCATION, and that is a defect frankZ found in their census and confirmed in
# mine. $PXX is overridable, so with PXX=/other/checkout/compiler/pascal26 the
# old line printed ANOTHER checkout's compiler sha beside THIS tree's commit --
# a pair that never existed. Worse in their version, and the half worth carrying
# here: the column LABEL was a fixed string naming one checkout, and a label that
# cannot follow the thing it names is the weaker half of the same defect rather
# than a defence. Deriving the directory from $PXX makes the label follow.
PXXDIR="$(CDPATH= cd -- "$(dirname -- "$PXX")/.." 2>/dev/null && pwd || echo "$ROOT")"
printf 'lz-census: compiler %s  (%s)\n' "$(sha256sum "$PXX" | cut -c1-12)" "$PXX"
printf 'lz-census: tree     %s%s  (the checkout $PXX came from: %s)\n' \
  "$(cd "$PXXDIR" && git log --format=%h -1 2>/dev/null || echo 'not a git tree')" \
  "$(cd "$PXXDIR" && [ -n "$(git status --porcelain 2>/dev/null)" ] && printf ' (DIRTY)' || true)" \
  "$PXXDIR"
# THE CORPUS'S OWN DIRTINESS IS THE HALF THAT GETS FORGOTTEN, and it is frankZ's
# point from devdocs/progress/census/lz_census.py rather than mine. lekkerzeilen is
# the owner's project and he edits it directly, so a census can be measuring a tree
# that exists on nobody else's box -- and the number then cannot be reproduced or
# compared with anyone's, while looking exactly like a number that can.
printf 'lz-census: corpus   %s%s\n' "$LZ" \
  "$(cd "$LZ" && [ -n "$(git status --porcelain 2>/dev/null)" ] && printf ' (DIRTY -- this run is not reproducible elsewhere)' || true)"
printf 'lz-census: corpus@  %s\n' "$(cd "$LZ" && git log --format=%h -1 2>/dev/null || echo 'not a git tree')"

if [ -n "$ONE" ]; then
  MODULES="$ONE"
else
  MODULES="$( cd "$LZ" && find lekkerzeilen -name '*.py' | sort )"
fi

NPASS=0; NFAIL=0
: > "$WORK/rows"
for m in $MODULES; do
  tag="$(printf '%s' "$m" | tr /. __ | sed 's/_py$//')"
  rc=0
  ( cd "$LZ" && "$PXX" --threadsafe "$m" "$WORK/$tag" ) > "$WORK/$tag.log" 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then
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
    # THE EXIT CODE IS CLASSIFIED, NOT JUST THE LOG -- frankZ's point, and the
    # reason it matters is that a CRASH PRINTS NO `error:` LINE. A census that
    # decides pass/fail by grepping for a diagnostic scores a segfault as CLEAN.
    # This script has always branched on the compiler's exit status, so it could
    # not score a crash as a pass; what it could not do is TELL YOU a crash from
    # an ordinary refusal, because both landed in the same "no diagnostic" bucket.
    # A signal death is a compiler bug and a refusal is usually the program's, so
    # they must not read alike.
    if [ "$rc" -ge 128 ]; then
      sig=$((rc - 128))
      signame="signal $sig"
      [ "$sig" = 11 ] && signame="SIGSEGV"
      [ "$sig" = 6 ]  && signame="SIGABRT"
      [ "$sig" = 9 ]  && signame="SIGKILL (OOM or a timeout, not necessarily a compiler fault)"
      err="CRASHED ($signame, rc=$rc) -- a COMPILER bug, not a program one${err:+ ; last diagnostic: $err}"
    fi
    [ -n "$err" ] || err="(rc=$rc, no diagnostic at all)"
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
# GROUPED BY MESSAGE, NOT BY MESSAGE-AND-LINE, and that is frankB's refinement
# rather than mine. Keying on both means a pair only groups while its line numbers
# agree -- so the moment a shared site becomes two real sites, the pair silently
# stops being reported at all, and the most interesting transition in the whole
# census produces no output. Keying on the MESSAGE and then printing the lines
# shows both states: same line is the cascade, different lines are separate sites,
# and you can watch one turn into the other across runs.
mark_cascades() {
  while IFS= read -r row; do
    case "$row" in
      FAIL*)
        mod="$(printf '%s' "$row" | sed 's/^FAIL \([^ ]*\) .*/\1/')"
        # The message with its line number removed, which is what identifies a
        # wall CLASS; and the line number on its own, which is what identifies a
        # SITE. The two questions need different keys.
        msg="$(printf '%s' "$row" | sed 's/^FAIL [^ ]* :: //; s/^pascal26:[0-9]*: //')"
        line="$(printf '%s' "$row" | sed -n 's/^FAIL [^ ]* :: pascal26:\([0-9]*\):.*/\1/p')"
        group="$(grep -F ":: " "$WORK/rows" | grep '^FAIL' \
                 | sed 's/^FAIL \([^ ]*\) :: pascal26:\([0-9]*\): /\1|\2|/' \
                 | awk -F'|' -v m="$msg" 'NF>=3 { r=$0; sub(/^[^|]*\|[^|]*\|/, "", r); if (r == m) print $1 ":" $2 }')"
        n=$(printf '%s\n' "$group" | grep -c . || true)
        if [ "${n:-0}" -gt 1 ]; then
          lines="$(printf '%s\n' "$group" | sed 's/.*://' | sort -u | tr '\n' ' ')"
          nlines=$(printf '%s\n' "$group" | sed 's/.*://' | sort -u | grep -c . || true)
          peers="$(printf '%s\n' "$group" | grep -v "^$mod:" | tr '\n' ' ')"
          if [ "${nlines:-0}" -eq 1 ]; then
            printf '%s\n      ^ cascade? %d subjects report this wall at the IDENTICAL line %s; likely ONE site reached through an import (also: %s)\n' \
              "$row" "$n" "$line" "$peers"
          else
            printf '%s\n      ^ %d subjects share this wall class at DIFFERENT lines (%s); separate sites, one cause (also: %s)\n' \
              "$row" "$n" "$lines" "$peers"
          fi
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
