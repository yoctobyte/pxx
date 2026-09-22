---
slug: bug-a-low-int64-renders-as-a-bare-minus-under-percent-d-and-abs-of-it-stays-negative
title: "A promotable int at exactly Low(Int64) prints as a bare `-` under `%d`, and `abs()` of it stays negative"
track: A
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: franks-5b
blocked-by: []
summary: "MECHANISM: every path that takes |v| by NEGATING IN PLACE is wrong at exactly Low(Int64) and correct at every other input, because it is the one value in the type whose magnitude the type cannot hold -- so -v overflows and leaves the sign bit set. It SPRINGS wherever a renderer or a numeric helper negates before it widens, and the population is that class, NOT the two instances below. This repo has now hit it through THREE paths: aarch64 WriteLn (done/bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes -- emitted -, did neg x0,x0, then ran the digit loop with sdiv where arm32 correctly used udiv); NilPy abs() (FIXED 2026-09-22, 185a81621 -- pyabs_v now routes 2^63 to the promotable arm it already had); and NilPy '%d' formatting, STILL OPEN -- \"%d\" % -9223372036854775808 emits a bare - with no digits. NARROWED: print(v) and \"%s\" % v are both CORRECT on the same value, and Pascal-side Format('%d', [Low(Int64)]) is correct too, so the open half is NilPy-specific and PER-FORMATTER, not per-value -- which is the shape that produces a fourth instance. Neighbours verified clean throughout: -2^62, -2^63+1, +2^63, -2^64. Grep for the other formatters' handlers, not for the value: the sibling is a SPELLING, not a shape."
---

# A promotable int at exactly Low(Int64) prints as `-` under `%d`

Two defects, one hazard. `Low(Int64)` = -9223372036854775808 has no positive
counterpart in Int64, so `-v` and `Abs(v)` both overflow for that one value.
`promocore.pas`'s `BFromInt` already carries a hand-written special case for it
and says so in a comment, which is evidence the hazard is known and was handled
in *one* place.

## Repro

```python
a = -9223372036854775808
print(a)            # -9223372036854775808   correct
print("%s" % a)     # -9223372036854775808   correct
print("%d" % a)     # -                      WRONG (bare sign, no digits)
print(abs(a))       # -9223372036854775808   WRONG (CPython: 9223372036854775808)
```

## The neighbours are all clean, which is the useful part

Measured 2026-09-22, same binary, same run:

| expression | pxx | CPython |
| --- | --- | --- |
| `"%d" % -4611686018427387904` (-2^62) | correct | correct |
| `"%d" % -9223372036854775807` (-2^63+1) | correct | correct |
| `"%d" % -9223372036854775808` (-2^63) | **`-`** | -9223372036854775808 |
| `"%d" % 9223372036854775808` (+2^63) | correct | correct |
| `"%d" % -18446744073709551616` (-2^64) | correct | correct |

So it is not "large negatives" and not "values past a machine word". It is
exactly the one value whose magnitude is not representable in the type being
used to hold it, which is the signature of a negate-before-widen.

## Why it has not been seen

**The ordinary spelling is correct.** `print(v)` and `%s` both work. Only `%d`
fails, and only at one value out of 2^64. Any test that prints its numbers the
usual way passes.

It was found because a fixture printed with `"%d" %` for column alignment, and
the value arrived from `-(1 << 63)`. Changing the readout to `print(a, b, c)`
made the same population pass with zero differences — **the readout, not the
value, was the defect**, which is the inverse of the usual trap: here the
instrument manufactured a disagreement out of a correct value.

## Attribution, established rather than assumed

Found while landing `247260d36`. **Not caused by it**: stashed that change,
rebuilt the compiler, re-ran — same 30 differing lines, and the two builds'
fixture output is byte-identical across all 269 rows.

## What would retire this

Both instances answering CPython on the row above, plus one row asserting
`abs(Low(Int64))` widens rather than negates in place. The fix wants to be in
whatever helper takes the magnitude, not in the two call sites, or the third
caller will have it too.

## Status 2026-09-22

- **`abs()` — FIXED**, `185a81621`. `pyabs_v` (`compiler/builtin/pylib.pas`)
  tested `i = Low(Int64)` **before** the negation and routed it to the
  promotable arm the same function already had for `VT_PROMO_INT64`. Checked
  before rather than after because afterwards the wrong answer and the input
  are the same bits. Regression test `test/nilpy_low_int64_boundary.py`, wired
  into the Makefile, asserts **arithmetic** on the result (`+1`, `//2`, `*2`,
  `-1`, and a compare past `High(Int64)`) rather than only its printed form —
  an `abs()` returning text that happens to print right would pass a
  printed-value check and fail every use.
- **`"%d" %` — OPEN.** Not fixed here, and the fixture says so explicitly so it
  cannot be read as covering it.

## The sibling was already fixed, and it holds the mechanism

`done/bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes` is the
same boundary through a different renderer, and its resolution is the clearest
statement of the class available: `EmitwriteIntA64` handles the sign first —
emit `-`, then `neg x0, x0` — so by the digit loop the register holds a
**magnitude**, and unsigned division is what a magnitude wants. aarch64 said
`sdiv`; arm32 said `udiv` with the comment *"divides the non-negative
magnitude"*. Signed division agreed for every value except the one where the
`neg` does not produce a non-negative result.

**So the fix shape is: after negating, treat the bits as UNSIGNED — or widen
instead of negating.** Both open and closed instances are that sentence.

## A separate residual, measured here and deliberately not fixed

`abs(True)` gives `True` where CPython gives `1`. **Pre-existing** — verified by
stashing the `abs` fix, rebuilding and re-running: that row is unchanged and
only the `Low(Int64)` row moved. Different mechanism (a bool keeping its tag
through a numeric helper, not a magnitude overflow), so it is noted rather than
folded in.
