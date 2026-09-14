#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Assert that a program built -dPXX_OBJTRACE never drives a refcount BELOW ZERO.
#
# WHY THIS EXISTS AND WHY A VALUE DIFF CANNOT REPLACE IT. An over-release is the
# mirror of a leak and it is just as invisible to an output comparison: the
# extra release lands AFTER the last read, so the program prints the right
# answer, frees a block something else still points at, and faults later in
# whatever moved into it. Measured 2026-09-14: `f(*xs)` with a variant operand
# over-released once per call, lekkerzeilen built 2184 such objects, and every
# reduction of it printed exactly what CPython printed.
#
# THE SPELLING IS THE WHOLE TRICK. objtrace does not write a negative refcount
# with a LEADING minus. It writes a TRAILING one (`objtrace r 0x... 1-`) or an
# unsigned wrap (`4294967294`), so `grep ' -[0-9]'` matches nothing and reports
# a clean run on a program with thousands of underflows. That grep cost an hour
# on 2026-09-14 and is why this check is a committed script and not a one-liner
# anyone retypes.
#
# Usage: assert_no_rc_underflow.sh <label> <command...>
#
# The command must be a binary built with -dPXX_OBJTRACE; the trace goes to
# stderr, one line per refcount event.
set -uo pipefail

label="${1:?usage: assert_no_rc_underflow.sh <label> <command...>}"
shift
[ "$#" -gt 0 ] || { echo "assert_no_rc_underflow[$label]: no command given" >&2; exit 2; }

trace=$(mktemp)
trap 'rm -f "$trace"' EXIT

"$@" >/dev/null 2>"$trace"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "assert_no_rc_underflow[$label]: the program itself failed (exit $rc)" >&2
  grep -av '^objtrace ' "$trace" | tail -5 >&2
  exit 1
fi

# ASSERT THE PRECONDITION. No trace means the binary was not built
# -dPXX_OBJTRACE, and "no underflow" would then be a true statement about
# nothing. A guard that cannot fire must not report PASS.
events=$(grep -ac '^objtrace ' "$trace")
if [ "${events:-0}" -lt 20 ]; then
  echo "assert_no_rc_underflow[$label]: only $events trace events — built without" >&2
  echo "  -dPXX_OBJTRACE, or the program allocated nothing. This proved nothing." >&2
  exit 1
fi

under=$(grep -ac '[0-9]-$\|42949672' "$trace")
if [ "${under:-0}" -ne 0 ]; then
  echo "assert_no_rc_underflow[$label]: $under release(s) drove a refcount NEGATIVE" >&2
  echo "  over $events trace events. A block was freed while still referenced." >&2
  grep -a '[0-9]-$\|42949672' "$trace" | head -5 >&2
  exit 1
fi

echo "assert_no_rc_underflow[$label]: OK — 0 underflows in $events events"
