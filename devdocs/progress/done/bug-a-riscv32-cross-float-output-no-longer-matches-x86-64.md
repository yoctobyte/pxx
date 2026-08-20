---
slug: bug-a-riscv32-cross-float-output-no-longer-matches-x86-64
track: A
prio: 65
status: done
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

## 2026-08-20 — BACK TO `urgent/` (owner): it BLOCKS PINNING, and that is a reason on its own

Owner: *"yes i figured, that regression breaks our pinning. that's a valid reason to mark it
urgent anyways."*

Correct, and it overturns the parking two paragraphs above — **on a different ground than the
one the parking was argued on.** Both things are true at once and the ticket now has to say so
without letting either erase the other:

- **As float work it is still low prio.** Digits and exponent width, values agreeing, the new
  rendering arguably the more correct one. Nothing here is worth a float engineer's afternoon.
- **As a PIN BLOCKER it is urgent**, because a red job in the matrix counts against
  `pin_shadow` regardless of how uninteresting its subject is. A stuck pin gate costs every
  lane, and the cost has nothing to do with floats.

**So the `F` tag is REMOVED and the track is plain `A`.** That is not a reclassification of the
subject — it is recognition that **the work that unblocks the pin is not float work at all.**
Option 1 in the analysis above is a *test* change: generate the expectation for the target's
own float depth instead of diffing riscv32's output against x86-64's. No float math, no
rendering change, no ULP judgement. Leaving it tagged `F` would park the bookkeeping along
with the physics, which is precisely how the red would have survived indefinitely.

### The general shape, worth carrying past this ticket

**A ticket can be low-prio by SUBJECT and urgent by CONSEQUENCE, and the deferral rules key on
subject only.** The F charter, the mandate, every lane rule — all of them answer "what is this
about?". None of them answers "what does leaving it red cost?". When those two disagree, the
consequence wins for *scheduling* while the subject still decides *who does it and how much
effort it deserves*.

This is the second time in one day that a stuck `pin_shadow` turned an unremarkable ticket into
a blocking one — see the cpyext decision, whose six reds held `would_pin` permanently false.
**Check the pin gate's red set before parking anything**, because parking stops dispatch and
never stops the failure.

### What the urgent work is, and what it is NOT

**Do:** make the riscv32/xtensa comparison use an expectation generated for that target's float
depth (`Makefile:8225` is a straight equality of the two outputs), or record the job as a
known-red with this ticket as its reason. Cheapest correct thing wins; it is bookkeeping.

**Do NOT:** change `PXXWriteFloatSci`, adjust digit counts, or chase the rendering difference.
The rendering is believed correct and that question stays low-prio.

## RESOLVED 2026-08-20 (frank2) — option 1, as a test change; no compiler source touched

Exactly the scope the last section set: bookkeeping. `PXXWriteFloatSci` is
untouched, no digit count moved, and the rendering question stays where it was
parked. `gate.sh quick` reports `SKIP FPC seed canary (compiler/ unchanged vs
origin/master)`, which is the mechanical confirmation that nothing in
`compiler/` moved.

### What changed

`test/test_cross_float.riscv32.expected` (new) plus the one job line, which was:

```make
./$(COMPILER) --target=riscv32 test/test_cross_float.pas $(TESTTMP)/test_rv32x_float
./$(COMPILER) test/test_cross_float.pas $(TESTTMP)/test_rv32x_float_x64
test "$$(tools/run_target.sh riscv32 $(TESTTMP)/test_rv32x_float)" = "$$($(TESTTMP)/test_rv32x_float_x64)"
```

and is now a `diff -u` against that recorded expectation. The x86-64 build of
this file is dropped, because it existed only to be the oracle; nothing else
referenced `test_rv32x_float_x64`. The `.expected` convention is the one 312
other tests already use, so this adds no new mechanism.

### Why the expectation is safe to record — it captures widths, not a rounding

This is the part worth checking rather than asserting, because "record the
current output" is how a wrong value gets blessed. It cannot happen here:
**every line that differs between the two targets is an exactly-representable
value.**

| line | x86-64 | riscv32 |
| --- | --- | --- |
| `s1 + s2` | ` 3.5000000000000000E+000` | ` 3.500000000E+00` |
| `s1 - s2` | `-5.0000000000000000E-001` | `-5.000000000E-01` |
| `s1 * s2` | ` 3.0000000000000000E+000` | ` 3.000000000E+00` |
| `s1 / s2` | ` 7.5000000000000000E-001` | ` 7.500000000E-01` |
| `i * s1` | ` 4.5000000000000000E+000` | ` 4.500000000E+00` |
| `i / 2` | ` 1.5000000000000000E+000` | ` 1.500000000E+00` |

3.5, -0.5, 3.0, 0.75, 4.5, 1.5 — no digit in the recorded file could be hiding
a wrong computation, because there is no inexact digit in it. The other 19
lines are byte-identical to x86-64's and stay that way in the expectation.

The set is also exactly what the diagnosis predicted: the six Single-typed
expressions. Four are Single/Single, one is Integer*Single, and `i / 2` is the
ordinal/ordinal case with no target type to take a depth from, so it falls to
the target's native depth — which is Single here. That is
`test_esp_float_depth_from_target.pas`'s documented behaviour, not a second
defect.

### Scope checked, not assumed

The two neighbouring cross-float jobs were re-measured on riscv32 rather than
reasoned about: `test_cross_float_return` and `test_cross_float_const` both
still agree with x86-64 byte for byte, so they keep the cheaper cross-equality
check and only the one file that actually diverges gets an expectation. No
xtensa job runs `test_cross_float` at all (`grep`ed, not assumed), so there is
no sibling arm to fix — despite the analysis above naming xtensa as equally
depth-reduced. i386 / aarch64 / arm32 are not depth-reduced and are unaffected.

### Gate

`make compiler/pascal26` (converged in 1 round) · the repro above ·
`tools/gate.sh quick` **GREEN** · the job itself re-run standalone and passing.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
