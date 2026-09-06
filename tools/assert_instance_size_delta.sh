#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# assert_instance_size_delta.sh — assert a class's InstanceSize differs between
# a 32-bit target and the 64-bit native build BY EXACTLY the pointer-width
# delta its layout predicts.
#
#   assert_instance_size_delta.sh <label> <target.raw> <native.raw> <nptrslots>
#
# Both raw files are the SAME program's stdout, one run under qemu for a 32-bit
# target and one run natively. Each must carry
#
#     ##METRIC instancesize <n>
#     ##METRIC pointersize  <n>
#
# WHY A RELATION AND NOT A NUMBER
# -------------------------------
# test_rtti printed InstanceSize in its body, so it could never match an
# x86-64 oracle and was SKIPPED on riscv32 for a month with the reason "differs
# per target by construction". True, and it is the wrong conclusion: a class
# holding N pointers is smaller on a 32-bit machine BY A KNOWN AMOUNT. The
# assertion is that amount. It carries no per-target constant, so it passes on
# every 32-bit target and prints a different correct number on each.
#
# THE MUST-DIFFER CONTROL IS THE POINT
# ------------------------------------
# The failure this really guards is the harness running the HOST binary while
# believing it ran the target -- the riscv32 batch's own header worries about
# exactly this ("SizeOf(Pointer) answers 4 under qemu-riscv32 and 8 native ...
# had it fallen back, every row would have passed"). An equality-only check
# CANNOT see it: if both sides are the host, both metrics match and a delta of
# zero looks like agreement. So we require the two runs to DISAGREE first, on
# pointersize and on instancesize, and only then check the size of the
# disagreement. A row that cannot fail when the target never ran is not a row.
#
# AND WE REFUSE A MISSING METRIC RATHER THAN READING IT AS ZERO
# ------------------------------------------------------------
# An absent ##METRIC line makes `awk` print nothing, arithmetic treats it as 0,
# and 0-0 == 0 passes a naive delta check. Every field is checked for presence
# before it is used, because the empty string is the value a vacuous run has.

if [ $# -ne 4 ]; then
    echo "assert_instance_size_delta.sh: usage: <label> <target.raw> <native.raw> <nptrslots>" >&2
    exit 2
fi

label="$1"; tfile="$2"; nfile="$3"; nptr="$4"

for f in "$tfile" "$nfile"; do
    if [ ! -s "$f" ]; then
        echo "$label: $f is missing or empty, so this check cannot run. The program under test produced no output; that is a RED, not a pass." >&2
        exit 1
    fi
done

metric() { awk -v k="$2" '$1=="##METRIC" && $2==k { print $3; found=1 } END { if (!found) exit 3 }' "$1"; }

t_size=$(metric "$tfile" instancesize) || { echo "$label: no '##METRIC instancesize' in $tfile" >&2; exit 1; }
t_ptr=$(metric  "$tfile" pointersize)  || { echo "$label: no '##METRIC pointersize' in $tfile"  >&2; exit 1; }
n_size=$(metric "$nfile" instancesize) || { echo "$label: no '##METRIC instancesize' in $nfile" >&2; exit 1; }
n_ptr=$(metric  "$nfile" pointersize)  || { echo "$label: no '##METRIC pointersize' in $nfile"  >&2; exit 1; }

for v in "$t_size" "$t_ptr" "$n_size" "$n_ptr"; do
    case "$v" in
        ''|*[!0-9]*) echo "$label: a ##METRIC value is empty or not a number (size/ptr target=$t_size/$t_ptr native=$n_size/$n_ptr)" >&2; exit 1 ;;
    esac
done

# MUST-DIFFER CONTROL 1: the two runs must be on different pointer widths.
if [ "$t_ptr" = "$n_ptr" ]; then
    echo "$label: MUST-DIFFER CONTROL FAILED. target and native both report SizeOf(Pointer)=$t_ptr, so the '32-bit target' run was almost certainly the HOST binary. Nothing below this line would have been able to fail." >&2
    exit 1
fi

# MUST-DIFFER CONTROL 1b: and the NATIVE side must be the WIDER one.
# Controls 1 and 2 only require the two runs to disagree, and the delta check
# below is SIGN-SYMMETRIC -- `want` and `got` both negate when the arguments are
# swapped, so they cancel and a reversed pair passes silently. That makes the
# argument order load-bearing while nothing asserts it, which is the same
# can't-fail shape this script exists to refuse. Verified 2026-09-06: with the
# target and native files exchanged, every check above passed and the script
# exited 0.
if [ "$n_ptr" -le "$t_ptr" ]; then
    echo "$label: DIRECTION CONTROL FAILED. native reports SizeOf(Pointer)=$n_ptr and target reports $t_ptr, so the file passed as the 32-bit target is the wider build. Arguments are <label> <target.raw> <native.raw> <nptrslots>; these two are swapped, or the 'native' oracle was not built natively." >&2
    exit 1
fi

# MUST-DIFFER CONTROL 2: a class holding pointers must not be the same size.
if [ "$t_size" = "$n_size" ]; then
    echo "$label: MUST-DIFFER CONTROL FAILED. InstanceSize is $t_size on both, but the class holds $nptr pointer-width slots and the widths differ ($t_ptr vs $n_ptr)." >&2
    exit 1
fi

want=$(( nptr * (n_ptr - t_ptr) ))
got=$((  n_size - t_size ))

if [ "$got" -ne "$want" ]; then
    echo "$label: InstanceSize delta is $got, expected $want." >&2
    echo "  native: InstanceSize=$n_size SizeOf(Pointer)=$n_ptr" >&2
    echo "  target: InstanceSize=$t_size SizeOf(Pointer)=$t_ptr" >&2
    echo "  relation: $nptr pointer-width slots * ($n_ptr - $t_ptr) = $want" >&2
    echo "  A delta that is not a whole number of pointer slots means a NON-POINTER field changed size or alignment across the ABI -- that is the finding, not this row." >&2
    exit 1
fi
exit 0
