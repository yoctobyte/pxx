#!/bin/sh
# The probe behind umbrella-pxx-compiles-fpc-itself: point pxx at every
# translation unit of FPC's own compiler and record the FIRST failure.
#
# FPC IS THE ORACLE, AND THAT IS THE WHOLE DESIGN. A corpus attempt's expensive
# mistake is not a missed bug, it is an INVOCATION error wearing the shape of a
# frontend bug: measured 2026-09-09, four of the first ten failures found this
# way were the probe's fault, and one of them (ccharset) is a unit `fpc` itself
# refuses under the same flags -- a unit the oracle cannot compile can never be
# evidence about us. So every unit is compiled by fpc FIRST, with the same unit
# and include paths, and a unit fpc rejects is reported as ORACLE-NO and is not
# a finding.
#
# THE FLAGS ARE FPC'S OWN BUILD'S, not a guess. FPC's compiler is not standalone
# source: every unit opens `{$i fpcdefs.inc}`, which derives ~40 defines from
# ONE build-time CPU define, and Makefile.fpc passes it as `-d$(CPC_TARGET)`
# (:381) together with `-Fux86 -Fix86` for x86_64 (:403) and
# `COMPILERSOURCEDIR=$(CPC_TARGET) systems` (:163). On our side that whole
# profile is one flag, `--mimic-fpc-compiler`, which exists for exactly this
# (feature-mimic-fpc-compiler-define-profile). Without it `globtype.pas:115
# unknown type: PInt` looks like a frontend bug and is not one.
#
# FPC IS A CORPUS: do not vendor it, do not reduce it, do not fix it. The
# question is only ever "does this compile", never "does our diagnostic match".
#
# EVERY FAILURE PER UNIT, NOT JUST THE FIRST -- AND THE COMPILER ALREADY DID
# THIS; THIS SCRIPT WAS THROWING IT AWAY. `ErrorRecover` carries a SEMANTIC
# failure past the diagnostic and keeps parsing, up to MAX_REPORTED_ERRORS (20,
# compiler/defs.inc), so a unit reports its independent mistakes and not merely
# the first. This probe piped that through `head -1` from the day it was
# written, which is why umbrella-pxx-compiles-fpc-itself spent five null rows
# saying the instrument that answers the SIZE question had never been built:
# it had, and the harness discarded its output. Measured 2026-09-11: behind
# cfileutl's `unknown type: TDoubleRec` sits `too many array initializer
# elements` at cpuinfo.pas:281, a second wall no first-failure census can see.
#
# WHY THE COUNT MATTERS MORE THAN THE LIST: a first-failure census ranks by
# QUEUE POSITION (CLAUDE.md), so a wall's population counts units stacked
# behind it and not work. errs= is not a work estimate either -- it is a
# recovered-error count and one cause can raise twenty of them, which is
# exactly what comphook did (20 rows, one missing `uses` binding). Read it as
# "is there anything behind this", never as a size.
#
# Usage:  tools/fpc_compiler_corpus_probe.sh [<fpc-compiler-dir>]
#         PXX_CORPUS_DETAIL=<dir>  also write <dir>/<unit>.err with every
#                                  diagnostic, for the walls-behind-the-wall
#         PXX_CORPUS_LIST=<file>   run only the units named in it (one path per
#                                  line) -- a full sweep is ~8 min and has been
#                                  lost twice when backgrounded; three
#                                  foreground chunks of an ASSERTED partition
#                                  finish. Assert it: the lists must union to
#                                  the glob, and the run must end with as many
#                                  distinct units as rows.
#         PXXBIN=<path>            the compiler under test (default: the tree's
#                                  own compiler/pascal26). Set it to compare two
#                                  binaries with everything else held fixed --
#                                  and note that lib/rtl reaches from the LIVE
#                                  tree even for the pinned binary, so a run
#                                  with PXXBIN=...pinned measures the OLD
#                                  compiler against the CURRENT RTL.
# Output: one line per unit -- BOTH-OK / ORACLE-NO / PXX-FAIL <unit> <first error>
#         PXX-FAIL rows carry `errs=N` when the unit reported more than one.
#         A final SUMMARY line carries the three counts and `truncated=N`.
#
# READ `truncated=` BEFORE YOU READ ANY errs= COUNT. It is the number of units
# whose error list was cut short by a parser give-up; while it is nonzero every
# errs= above is a LOWER BOUND, and so is any how-much-is-left figure derived
# from them. Measured 2026-09-16: one give-up hid 357 error lines across 134
# units. truncated=0 is what turns these counts into counts.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
F=${1:-/home/neo/src/fpc-trunk/compiler}
if [ ! -d "$F" ]; then echo "corpus not found: $F" >&2; exit 2; fi
if ! command -v fpc >/dev/null 2>&1; then
  echo "fpc is the oracle here and it is absent: this probe cannot run" >&2
  exit 2
fi
OPT="-dx86_64 -Fu$F -Fu$F/x86_64 -Fu$F/systems -Fu$F/x86 -Fi$F -Fi$F/x86_64 -Fi$F/x86"
PXXBIN=${PXXBIN:-$R/compiler/pascal26}
if [ ! -x "$PXXBIN" ]; then echo "no compiler at $PXXBIN" >&2; exit 2; fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$R" || exit 1

# PXX_CORPUS_LIST: run only the units named in this file, one PATH per line.
# A full sweep is ~8 minutes, and a backgrounded one has been lost twice at
# ~150/207 with the wrapper reporting an unrelated cause; three foreground
# chunks of a partition finish, and a partition can be ASSERTED (the lists must
# union to the glob, and the run must end with as many distinct units as rows).
if [ -n "${PXX_CORPUS_LIST:-}" ]; then
  SUBJECTS=$(cat "$PXX_CORPUS_LIST")
else
  SUBJECTS=$(ls "$F"/*.pas)
fi

n_ok=0; n_oracle=0; n_fail=0; n_trunc=0
for p in $SUBJECTS; do
  u=$(basename "$p" .pas)
  printf 'program d;\nuses %s;\nbegin end.\n' "$u" > "$W/d.pas"
  fo=$(timeout 120 fpc -Mobjfpc $OPT -FU"$W" -o"$W/dfpc" "$W/d.pas" 2>&1 \
       | grep -E '^[^ ].*(Error|Fatal):' | head -1)
  if [ -n "$fo" ]; then n_oracle=$((n_oracle + 1)); printf 'ORACLE-NO  %-16s %s\n' "$u" "$fo"; continue; fi
  timeout 120 "$PXXBIN" -Mobjfpc --mimic-fpc-compiler $OPT \
       "$W/d.pas" "$W/dpxx" > "$W/pxx.out" 2>&1
  grep -v 'warning:' "$W/pxx.out" | grep -v '^ok:' > "$W/pxx.err"
  po=$(head -1 "$W/pxx.err")
  ne=$(grep -c 'error:' "$W/pxx.err")
  if [ -n "${PXX_CORPUS_DETAIL:-}" ] && [ -s "$W/pxx.err" ]; then
    mkdir -p "$PXX_CORPUS_DETAIL" && cp "$W/pxx.err" "$PXX_CORPUS_DETAIL/$u.err"
  fi
  # A PARSER GIVE-UP TRUNCATES THIS UNIT'S ERROR LIST, and nothing else in the
  # output says so. `internal parser bug: statement made no progress in block`
  # ABANDONS THE BLOCK, so every failure after it is invisible -- to the detail
  # file just as thoroughly as to the head. Measured 2026-09-16: one such
  # give-up in cfileutl.pas hid 357 error lines across 134 units, three of them
  # error KINDS this corpus had never reported. That is a blindness INSIDE the
  # instrument built to cure first-error blindness, so it is counted here rather
  # than left for a reader to grep for: a summary saying trunc=0 is the only
  # thing that makes an errs= count a count instead of a lower bound.
  if grep -q 'statement made no progress' "$W/pxx.err"; then n_trunc=$((n_trunc + 1)); fi
  if [ -z "$po" ]; then n_ok=$((n_ok + 1)); printf 'BOTH-OK    %s\n' "$u"
  elif [ "$ne" -gt 1 ]; then n_fail=$((n_fail + 1)); printf 'PXX-FAIL   %-16s errs=%-3s %s\n' "$u" "$ne" "$po"
  else n_fail=$((n_fail + 1)); printf 'PXX-FAIL   %-16s %s\n' "$u" "$po"; fi
done

printf 'SUMMARY    both-ok=%s oracle-no=%s pxx-fail=%s truncated=%s\n' \
       "$n_ok" "$n_oracle" "$n_fail" "$n_trunc"
if [ "$n_trunc" -gt 0 ]; then
  echo "SUMMARY    WARNING: $n_trunc unit(s) hit a parser give-up -- their error" \
       "lists are TRUNCATED and every errs= count above is a LOWER BOUND" >&2
fi
