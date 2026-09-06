---
slug: bug-a-a-float-assigned-to-an-integer-lvalue-moves-the-bits-instead-of-converting
title: "A float-valued RHS stored into an integer LVALUE moves the BIT PATTERN — `Comp := 4.7` gives 4616977747989548237"
track: A
prio: 45
type: bug
status: done
owner: frankwasm
created: 2026-09-06
found-by: frankS
blocked-by: []
summary: "`Co := D` with `Co: Comp; D: Double` stores the IEEE-754 BITS of the double into the integer, so `D := 4.7; Co := D` prints 4616977747989548237 where fpc 3.2.2 prints 5. One direction only — int-to-float (`D := I`, `S := D`) is correct and matches fpc. THE COMP FACE IS A REAL DEFECT: fpc ACCEPTS `Comp := <real>` because Comp is a real-valued type there, so this is correct FPC source silently producing garbage, and it is what the fpc-testsuite row tstring4 hits. The Int64/LongInt face (`I := D` -> 4616977747989548237, `L := D` -> -858993459) is code fpc REJECTS outright (`Incompatible types: got \"Double\" expected \"Int64\"`), so accepting it is not itself a defect — printing a plausible wrong number for it is. pxx maps `comp` to `tyInt64` (pasparser_lval.inc:7596), so the compiler CANNOT distinguish the case fpc accepts from the case fpc rejects: one key, two required answers."
---

# Measured 2026-09-06, compiler `faa41e4b920f`

```pascal
var Co: Comp; D: Double; I: Int64; L: LongInt;
D := 4.7;
I := Round(D);  { pxx 5                    fpc 5                        }
Co := Round(D); { pxx 5                    fpc 5.0000000000000000E+0000 }
Co := D;        { pxx 4616977747989548237  fpc 5.0000000000000000E+0000 }
I  := D;        { pxx 4616977747989548237  fpc REFUSES                  }
L  := D;        { pxx -858993459           fpc REFUSES                  }
```

`4616977747989548237` is exactly the IEEE-754 double encoding of 4.7, and
`-858993459` is its low 32 bits. Nothing is converted; the bits are moved.

**The reverse direction is correct and was measured, not assumed:** `D := I`
(7 -> 7.00), `D := L` (9 -> 9.00) and `S := D` (3.5 -> 3.50) all match fpc.

## Why it is not caught

`AssignKindsIncompatible` **deliberately** stands down on numeric pairs — the
note in `ir.inc` says so in as many words: *"Numeric pairs are unaffected: that
rule returns False for every int/float combination, so `d := i * 2` is
untouched."* That is right for the direction it was written for. The store then
lowers as a plain move, and no float-to-int conversion is emitted. The machinery
exists and is reachable from the intrinsics — `Round` and `Trunc` lower through
`cvtsd2si`/`cvttsd2si` — so this is a missing edge, not a missing capability.

## The fork, and why it is not a one-line fix

**`Comp` is `tyInt64`.** The two faces need OPPOSITE answers and the type system
cannot tell them apart:

| spelling | fpc | what pxx should do |
| --- | --- | --- |
| `Comp := <real>` | accepted, rounds | **convert** |
| `Int64 := <real>` | REFUSED | refuse (or convert) |

**Recommended default, if nobody wants the type-system change: CONVERT (round)
on a float-to-integer store.** It makes the `Comp` face correct, and it turns
the `Int64` face from a silent bit pattern into a defensible value while still
only affecting code fpc rejects — us accepting what fpc rejects is not a defect
(the goal doc), but *printing a plausible wrong number* for it is exactly the
trap this repo keeps paying for. Refusing instead would be more informative and
fpc-compatible, and it **cannot be done without making `Comp` distinguishable
from `Int64` first**, because it would break the one face fpc accepts.

## Blast radius — why it was filed rather than fixed on the spot

The change is in the IR store path, which every frontend shares, and a
float-to-integer store is not a shape a Track P quick tier proves. It wants a
full tier. Filed by frankS from the fpc-testsuite corpus (rung 1) rather than
taken, because the corpus's job is to narrow and this narrowed cleanly.

`tstring4.pp` is where it surfaced; that row stays skipped on its own
(`wontfix:` — it reads ansistring header words), and this defect is one of the
divergences hiding behind it.

## Log
- 2026-09-06 — resolved, commit 3e2bca576.

# Resolved 2026-09-06 — frankwasm, `3e2bca576`

Fixed in `ir.inc`'s `AN_ASSIGN` arm: a float RHS into a `TypeIsMachineInt`
destination is wrapped in the `-204` Round intrinsic, which all seven backends
already implement. The conversion had lived in the BACKEND — only x86-64 and
aarch64 had a float→int store arm at all, and x86-64's is `CProgramMode`-gated,
so in Pascal mode five of seven had none. Per-backend would have written one
rounding rule seven times.

ROUND, not truncate, measured: fpc 3.2.2 gives 4.7→5, 2.5→2, 3.5→4, -4.7→-5,
-2.5→-2, 0.5→0, 1.5→2 — ties to EVEN, exactly what `-204` emits. pxx now
matches all seven.

Test `test/test_double_to_integer_lvalue_rounds.pas`, wired directly after its
variant sibling `test_variant_double_to_integer_rounds.pas` in the Makefile.
That sibling is the point: it fixed `i := v` for a VARIANT holding a double and
scoped itself carefully, while the plain `i := D` beside it was never a variant
conversion and so was never covered. One rule, two paths, second one wrong.

Positive control: 19 failures under the pin, 0 at HEAD. The control also
corrected the new test's own comment — a 32-bit target takes the LOW HALF of
the payload, 0 for many doubles (`I := 7.5` answered 0, not a large number), so
any row expecting 0 into a 32-bit target is non-discriminating. One such row
exists and is labelled.

## On this ticket's "one key, two required answers"

Both faces now get the SAME answer and that is sufficient. The Comp face (which
fpc accepts) needed the rounded value and has it. The Int64/LongInt face is code
fpc REJECTS, so accepting it is not itself a defect — only "printing a plausible
wrong number" for it was, and it no longer does. What still separates the two is
a DIAGNOSTIC we do not emit, and a differing diagnostic is deferred. The
`comp` → `tyInt64` aliasing did not have to be unpicked to close this.

## Residual, with an owner

The VALUE matches; the RENDERING does not. fpc prints Comp as
`5.000000000000000000E+0000` (real-valued type there), pxx prints `5`
(`comp` aliases `tyInt64`). Observable output differing on source someone meant
to write, so it is a separate question — filed as
`bug-a-comp-renders-as-an-integer-because-it-aliases-int64`.

The ticket's citation `pasparser_lval.inc:7596` for the mapping has drifted; it
is **8114** today.
