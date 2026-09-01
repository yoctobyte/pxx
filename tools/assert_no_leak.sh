#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Assert that a program built -dPXX_ALLOC_CENSUS frees what it allocates.
#
# WHY THIS EXISTS RATHER THAN A CROSS-TARGET DIFF. The managed-string leak rows
# next to this one compare a target's census against the x86-64 build of the
# same source, which catches a backend that diverges -- and is BLIND to a leak
# every backend shares. `Length(F(i))` leaked one handle per evaluation on all
# six backends identically (allocs=921 frees=0 live=921); the differential rows
# would have compared two equally wrong numbers and passed. This is the absolute
# check that catches that class.
#
# Usage: assert_no_leak.sh <label> <max-live> <command...>
#
# Reads the LAST `pxx-census:` line the command prints. That line is the closest
# thing to a total (the census reports on a geometric threshold and there is no
# exit hook), so `live` is within ~12.5% of the true residue -- which is why the
# bound is a threshold and not an equality. A leak of the kind this guards is
# proportional to the loop count and clears any sane bound by orders of
# magnitude; a bound in the low hundreds separates "a handful still live at
# exit" from "nothing was ever freed".
set -uo pipefail

label="${1:?usage: assert_no_leak.sh <label> <max-live> <command...>}"
maxlive="${2:?missing max-live}"
shift 2
[ "$#" -gt 0 ] || { echo "assert_no_leak[$label]: no command given" >&2; exit 2; }

out=$("$@" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "assert_no_leak[$label]: the program itself failed (exit $rc)" >&2
  echo "$out" | tail -5 >&2
  exit 1
fi

line=$(printf '%s\n' "$out" | grep '^pxx-census:' | grep 'allocs=' | tail -1)

# ASSERT THE PRECONDITION, not just the comparison. No census line means the
# program was not built -dPXX_ALLOC_CENSUS, or allocated nothing at all -- and
# in both cases a "no leak" verdict would be true about nothing. A guard that
# cannot fire must not report PASS.
if [ -z "$line" ]; then
  echo "assert_no_leak[$label]: NO CENSUS OUTPUT — built without -dPXX_ALLOC_CENSUS," >&2
  echo "  or the program never allocated. Either way this check proved nothing." >&2
  exit 1
fi

allocs=$(printf '%s' "$line" | grep -o 'allocs=[0-9]*' | cut -d= -f2)
frees=$(printf '%s' "$line" | grep -o 'frees=[0-9]*'  | cut -d= -f2)
live=$(printf '%s' "$line" | grep -o 'live=[0-9]*'    | cut -d= -f2)

# A run that allocated almost nothing cannot demonstrate the absence of a
# per-iteration leak either: the subject has to have run.
if [ "${allocs:-0}" -lt 100 ]; then
  echo "assert_no_leak[$label]: only $allocs allocations — too few to show anything." >&2
  echo "  $line" >&2
  exit 1
fi

if [ "${live:-0}" -gt "$maxlive" ]; then
  echo "assert_no_leak[$label]: LEAK — live=$live exceeds $maxlive" >&2
  echo "  allocs=$allocs frees=$frees" >&2
  echo "  $line" >&2
  exit 1
fi

echo "assert_no_leak[$label]: ok (allocs=$allocs frees=$frees live=$live, bound $maxlive)"
