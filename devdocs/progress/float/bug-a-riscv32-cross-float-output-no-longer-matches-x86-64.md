---
slug: bug-a-riscv32-cross-float-output-no-longer-matches-x86-64
track: A+F
prio: 20
status: parked
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

## 2026-08-20 — MOVED urgent/ -> float/, prio 60 -> 20 (owner correction)

**Filed and ranked in the wrong place, and the ticket's own body says so.** It reads:
*"The VALUES agree — this is digits and exponent width, not arithmetic."* Digit counts and
exponent form are **exactly** what the F charter names as float FORMATTING, which is Track F
and low prio by definition. It sat in `urgent/` at p60 where `ready`/`next` rank it, which is
the one thing F tickets must not do.

The owner caught it: *"there's a float ticket sitting in urgent, same issue — float work is
deferred."*

**Why the regression framing did not save it.** The corollary "a regression is worked at the
priority of being red regardless of subject" is what put it in `urgent/`. That corollary is
overruled here by the owner, and on the merits it should not have applied anyway: this is not
a case where correct behaviour became incorrect. The ticket's own analysis says **the new
rendering is arguably the CORRECT one** — a `Single` printed as a `Single`, now that
`PXXWriteFloatSci` can ask for the 10-significant-digit form — and the defect is the TEST's
assumption that a float-depth-reduced target's output is byte-comparable with x86-64's. A red
job whose recommended fix is to change the expectation is not a regression in the compiler.

**Rank the mechanism, never the datatype** — and here the mechanism *is* the rendering, so F
is right rather than being a place to hide something.

### What stays true while this is parked, and someone should see it

`test-riscv32#src:test/test_cross_float.pas` **stays red in Track T's matrix.** Parking the
ticket does not make the job green; it only stops the ticket being dispatched. So the red
continues to appear in full-tier reports and to count against `pin_shadow` unless allowlisted.

That is a Track T bookkeeping question, not a reason to unpark this: either the job is
recorded as a known-red with this ticket as its reason, or the trivial half of option 1
(generate the expectation for the target's own float depth, rather than diffing against
x86-64's output) is done as a **test** fix by whoever owns that Makefile line. Neither is
float-accuracy work. Flagged so the red does not get re-triaged from scratch in a week by
someone who cannot see this ticket in `ready`.
