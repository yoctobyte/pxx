#!/bin/bash
# Guard the guard: run tools/frozen_tree_guard.sh's own positive control.
#
# frozen_tree_guard.sh exists to refuse a verdict from a run whose inputs moved
# underneath it. Its whole value is that it can FAIL, so its selftest is the
# thing that must not rot -- a contamination guard that has quietly stopped
# detecting contamination prints the same reassuring line as one that works.
#
# The selftest's own shape is what this wires in: four rows that must go RED
# (head moved, tracked-diff moved, compiler binary moved, check-without-start)
# and one that must stay GREEN (nothing moved). Without that last row the other
# four would pass against a guard that always reds, which is the same animal as
# one that never does.
#
# Wired by NAME, not by this file listing rows: `make tools-devtest-sh` globs
# tools/*devtest*.sh, so this runs wherever that target runs and needs no
# Makefile edit -- which matters, because a Makefile edit is how this whole
# family of mistakes started.
set -u

here=$(cd "$(dirname "$0")" && pwd)
guard="$here/frozen_tree_guard.sh"

if [ ! -x "$guard" ]; then
    echo "FAIL: $guard is missing or not executable" >&2
    exit 1
fi

out=$("$guard" selftest 2>&1)
rc=$?
echo "$out"

if [ $rc -ne 0 ]; then
    echo "FAIL: frozen_tree_guard selftest is RED -- the contamination guard" >&2
    echo "      cannot be trusted to detect contamination." >&2
    exit 1
fi

# Assert the selftest actually RAN its rows rather than exiting 0 early. A
# script that prints nothing and exits 0 is the failure mode this repo keeps
# recording as "four build failures read as four clean zeros", and rc alone
# cannot tell the two apart.
rows=$(printf '%s\n' "$out" | grep -c '^  ok   t_')
if [ "$rows" -lt 5 ]; then
    echo "FAIL: selftest exited 0 but reported only $rows passing row(s)." >&2
    echo "      Expected every row to run. rc=0 with no rows is not a pass." >&2
    exit 1
fi

echo "frozen-tree-guard devtest: selftest green, $rows row(s) asserted"
