#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# The byte DISTANCE between two members of one aggregate, read out of a
# `PXXDBG=a.reclayout` log.
#
# WHY A DISTANCE AND NOT AN OFFSET. The caller compares the same aggregate
# across pxx's C, Pascal and NilPy frontends, and a NilPy instance carries an
# 8-byte header in front of its first field while a C struct does not. Raw
# offsets would report that header as a disagreement. The distance is the part
# the psABI actually constrains, and it carries no expected width -- so the
# caller can assert a RELATION and stay correct on every target.
#
# It prints `MISSING` rather than a number when either field was not found, and
# the caller MUST branch on that. Two different failures both produce silence
# otherwise: a compile that died before layout prints no lines at all, and a
# renamed field prints lines that do not match. An empty delta compared against
# another empty delta AGREES, so a run where nothing was measured would pass as
# a run where everything agreed.
#
# Usage: tools/reclayout_delta.sh <a.reclayout log> <RECORD> <first> <second>
set -u

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <log> <record> <field1> <field2>" >&2
  exit 2
fi

[ -f "$1" ] || { echo "MISSING"; exit 0; }

awk -v r="$2" -v a="$3" -v b="$4" '
  $0 ~ ("^PXXDBG a\\.reclayout rec=" r " ")  { inr = 1; o1 = ""; o2 = ""; next }
  inr && $0 ~ /^PXXDBG a\.reclayout rec=/    { inr = 0 }
  inr && $2 == "a.reclayout" {
    name = ""; off = "";
    for (i = 1; i <= NF; i++) {
      if (substr($i, 1, 4) == "fld=") name = substr($i, 5);
      if (substr($i, 1, 4) == "off=") off  = substr($i, 5);
    }
    if (name == a) o1 = off;
    if (name == b) o2 = off;
  }
  END {
    if (o1 == "" || o2 == "") { print "MISSING"; exit 0 }
    print (o2 - o1)
  }
' "$1"
