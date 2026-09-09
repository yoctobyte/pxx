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
# Usage:  tools/fpc_compiler_corpus_probe.sh [<fpc-compiler-dir>]
# Output: one line per unit -- BOTH-OK / ORACLE-NO / PXX-FAIL <unit> <first error>
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
  po=$(timeout 120 "$R"/compiler/pascal26 -Mobjfpc --mimic-fpc-compiler $OPT \
       "$W/d.pas" "$W/dpxx" 2>&1 | grep -v 'warning:' | grep -v '^ok:' | head -1)
  if [ -z "$po" ]; then printf 'BOTH-OK    %s\n' "$u"
  else printf 'PXX-FAIL   %-16s %s\n' "$u" "$po"; fi
done
