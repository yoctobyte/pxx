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
# Output: one line per unit -- BOTH-OK / ORACLE-NO / PXX-FAIL <unit> <first error>
#         PXX-FAIL rows carry `errs=N` when the unit reported more than one.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
F=${1:-/home/neo/src/fpc-trunk/compiler}
if [ ! -d "$F" ]; then echo "corpus not found: $F" >&2; exit 2; fi
if ! command -v fpc >/dev/null 2>&1; then
  echo "fpc is the oracle here and it is absent: this probe cannot run" >&2
  exit 2
fi
OPT="-dx86_64 -Fu$F -Fu$F/x86_64 -Fu$F/systems -Fu$F/x86 -Fi$F -Fi$F/x86_64 -Fi$F/x86"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$R" || exit 1
for p in "$F"/*.pas; do
  u=$(basename "$p" .pas)
  printf 'program d;\nuses %s;\nbegin end.\n' "$u" > "$W/d.pas"
  fo=$(timeout 120 fpc -Mobjfpc $OPT -FU"$W" -o"$W/dfpc" "$W/d.pas" 2>&1 \
       | grep -E '^[^ ].*(Error|Fatal):' | head -1)
  if [ -n "$fo" ]; then printf 'ORACLE-NO  %-16s %s\n' "$u" "$fo"; continue; fi
  timeout 120 "$R"/compiler/pascal26 -Mobjfpc --mimic-fpc-compiler $OPT \
       "$W/d.pas" "$W/dpxx" > "$W/pxx.out" 2>&1
  grep -v 'warning:' "$W/pxx.out" | grep -v '^ok:' > "$W/pxx.err"
  po=$(head -1 "$W/pxx.err")
  ne=$(grep -c 'error:' "$W/pxx.err")
  if [ -n "${PXX_CORPUS_DETAIL:-}" ] && [ -s "$W/pxx.err" ]; then
    mkdir -p "$PXX_CORPUS_DETAIL" && cp "$W/pxx.err" "$PXX_CORPUS_DETAIL/$u.err"
  fi
  if [ -z "$po" ]; then printf 'BOTH-OK    %s\n' "$u"
  elif [ "$ne" -gt 1 ]; then printf 'PXX-FAIL   %-16s errs=%-3s %s\n' "$u" "$ne" "$po"
  else printf 'PXX-FAIL   %-16s %s\n' "$u" "$po"; fi
done
