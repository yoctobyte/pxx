#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Assert that a program built -dPXX_ALLOC_CENSUS allocates NO MORE than a bound.
#
# WHY THIS EXISTS RATHER THAN assert_no_leak.sh. That one asks whether what was
# allocated came back; this one asks whether it should have been allocated at
# all. A string literal is already a managed string in .data, so `s := 'yy'`
# should allocate nothing -- but a backend that copies it to the heap and then
# frees it correctly is INVISIBLE to a leak check (frees track allocs, live is
# flat) and invisible to a cross-target differential too, because the census
# counters are the only place the difference shows.
#
# WHY A CEILING AND NOT A ZERO. A program that allocates nothing prints no
# census line at all, and "no output" is a verdict that passes by measuring
# nothing -- the exact failure assert_no_leak.sh refuses. So the subject program
# must contain a deliberate allocator, the census line must exist, and the
# question is whether the total is near that floor or near the loop count.
#
# Usage: assert_alloc_ceiling.sh <label> <max-allocs> <command...>
set -uo pipefail

label="${1:?usage: assert_alloc_ceiling.sh <label> <max-allocs> <command...>}"
maxalloc="${2:?missing max-allocs}"
shift 2
[ "$#" -gt 0 ] || { echo "assert_alloc_ceiling[$label]: no command given" >&2; exit 2; }

out=$("$@" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "assert_alloc_ceiling[$label]: the program itself failed (exit $rc)" >&2
  echo "$out" | tail -5 >&2
  exit 1
fi

line=$(printf '%s\n' "$out" | grep '^pxx-census:' | grep 'allocs=' | tail -1)

# ASSERT THE PRECONDITION. No census line means the program was not built
# -dPXX_ALLOC_CENSUS, or its deliberate allocator did not run. Either way a
# "under the ceiling" verdict would be true about nothing, and this check is
# specifically about a number that gets SMALLER when things go right -- so it is
# the one most able to pass by measuring nothing. It must not.
if [ -z "$line" ]; then
  echo "assert_alloc_ceiling[$label]: NO CENSUS OUTPUT — built without" >&2
  echo "  -dPXX_ALLOC_CENSUS, or the subject never allocated. A ceiling check" >&2
  echo "  with no floor proves nothing; the program must allocate deliberately." >&2
  exit 1
fi

allocs=$(printf '%s' "$line" | grep -o 'allocs=[0-9]*' | cut -d= -f2)

if [ "${allocs:-0}" -gt "$maxalloc" ]; then
  echo "assert_alloc_ceiling[$label]: TOO MANY — allocs=$allocs exceeds $maxalloc" >&2
  echo "  $line" >&2
  exit 1
fi

echo "assert_alloc_ceiling[$label]: ok (allocs=$allocs, ceiling $maxalloc)"
