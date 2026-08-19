---
slug: bug-a-riscv32-cross-float-output-no-longer-matches-x86-64
track: A+F
prio: 60
status: urgent
---

# `test-riscv32#src:test/test_cross_float.pas` — the two sides print the same numbers at different widths

One of the 13 jobs in `regression-cascade-21f098e32a95`, and the one native
testing structurally cannot see.

## Reproduced at HEAD

    ./compiler/pascal26 --target=riscv32 test/test_cross_float.pas /tmp/rv
    ./compiler/pascal26                  test/test_cross_float.pas /tmp/rv_x64
    tools/run_target.sh riscv32 /tmp/rv   vs   /tmp/rv_x64

    x86-64                      riscv32
     3.5000000000000000E+000     3.500000000E+00
    -5.0000000000000000E-001    -5.000000000E-01
     3.0000000000000000E+000     3.000000000E+00
     7.5000000000000000E-001     7.500000000E-01
     7.5000000000000000E+000     7.5000000000000000E+000   <- this one agrees

The Makefile line is a straight equality of the two outputs
(`Makefile:8225`), so any width difference is a failure. **The VALUES agree** —
this is digits and exponent width, not arithmetic.

## Attribution — by the shape of the change, not a bisect

`354f734c1 fix(A): the scientific float writer takes no parameters — two
tickets, one change`, in the range. Its own message says what it did:
`PXXWriteFloatSci` used to hardcode 16 fractional digits and a 3-digit exponent,
and now a **Single** can ask for its 10-significant-digit / 2-digit-exponent
form. riscv32 (and xtensa) reduce float depth from the target — a `Double`
there IS a Single, `test_esp_float_depth_from_target.pas` pins exactly that — so
those values now render in the Single form while x86-64 renders them as Doubles.
The one line that still agrees is the one whose value is exact in both.

That reading is consistent with every line of the diff, but it is an argument
from the change, not a bisect. Bisecting it is cheap if wanted: the clone
recipe is in
`bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method`.

**It is NOT `da53bbd26`** (the eight `PXX_NO_*` omission defines): those all
default OFF, nothing in the tree builds with one set, so a default cross build
sees byte-identical source. That prior came from frank3 and this triage agrees
with it.

## The actual question — and it is not "revert"

The new rendering is arguably the CORRECT one: a Single printed as a Single. If
so the defect is the TEST's assumption that a float-depth-reduced target's
output is byte-comparable with x86-64's, which stopped being true the moment the
writer learned the difference. Options:

1. Compare riscv32/xtensa against an expectation generated for **that** target's
   float depth, not against x86-64's output. Keeps the new, more correct
   rendering. *Recommended.*
2. Make the sci writer's width depend on the DECLARED type rather than the
   storage depth, so a `Double` source prints Double-width even where it is
   stored as a Single. Preserves cross-target output equality; arguably prints a
   precision the target does not have.
3. Revert the width change on reduced-depth targets. Reopens the two tickets
   `354f734c1` closed.

Track F by subject (float FORMATTING — digit counts and exponent form are
explicitly F), Track A by file ownership; obeys A's gate. Filed rather than
fixed because option 1 vs 2 is a real call about what a cross-target float test
asserts.

## Gate

`make compiler/pascal26`, the two compiles above, `tools/run_target.sh riscv32`,
then `tools/gate.sh quick`.

*Filed by frank2-C during cascade triage; not claimed.*
