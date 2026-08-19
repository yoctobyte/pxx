---
track: A
prio: 35
type: feature
blocked-by: []
summary: "The inliner takes only int/ordinal leaves — it rejects any function returning a float or a record. Measured on lib/rtl/math.pas's double-double kernels: hand-inlining the exact same arithmetic took a sin kernel from 7.96 us to 2.11 us, BIT-IDENTICAL, so ~74% of that path's cost was call overhead the inliner already knows how to remove for integers."
---

# Inline float-returning and record-returning leaf functions

- **Type:** feature (optimizer — **Track O**, file-owned by **Track A**:
  `compiler/**`, the inline pass). Filed by Track B, which measured it and does
  not edit the optimizer.
- Found 2026-08-15 while making `lib/rtl/math.pas`'s transcendentals fast.

## The measurement

One `sin` kernel call, the same arithmetic three ways:

| | time | accuracy |
| --- | --- | --- |
| double-double Taylor over the dd primitives | 7.96 us | correctly rounded |
| **identical arithmetic, hand-inlined by me** | **2.11 us** | correctly rounded, **bit-identical** |
| plain-double minimax kernel | 0.029 us | ~1 ulp |

Row 2 is the one that matters here. Nothing about the computation changed — same
operations, same order, same output bits — only the calls went away. **3.8x, for
free, from a transform the compiler already performs on integer code.**

The dd kernels are the extreme case (a `DdMul` is ~10 float ops behind a call,
and a Horner loop makes 26 of them), but the shape is everywhere: small leaf
functions returning `Double` or a two-field record are exactly what numeric
library code is made of.

## Scope correction (measured later the same day) — read before ranking this

The 3.8x above does **not** generalize. Measured on the plain-double fast `Sin`
path, hand-inlining every call into one function bought only **1.2x** (77 ms ->
65 ms per 1M). The dd kernels are an outlier precisely because the callee is so
small that the call dominates it.

The 7.2x on that same workload is the **value model**, not calls:
[[feature-opt-float-register-temporaries]], which carries a Double as raw bits
in RAX and so emits three GPR<->XMM transfers plus a stack round-trip per
operation — 316 `movq` in one function where gcc emits zero.

So: this ticket is real and cheap, but it is the ~20% and that one is the 7x.
Rank accordingly, and do not let this one be mistaken for the fix.

## What the inliner does today

It accepts int/ordinal-returning leaves and rejects anything returning a float
or a record. Worth checking whether that is a deliberate ABI-return-slot
restriction or just where the implementation stopped — the by-value float return
path and the record return path both work correctly for ordinary calls, so the
values themselves are not the obstacle.

## Suggested scope

Leaf functions only, no branches or one branch, returning `Double`/`Single` or a
record of two such fields — which covers `DdMul`, `Dd2Sum`, `DdFast2Sum`,
`DdAdd`, `DdMulD`, `DdBits` and their peers, i.e. the whole hot set. That is a
much smaller change than general float inlining and captures most of the 3.8x.

Per Track O's rule, land behind `-O3` and promote to `-O2` per-pass after the
full gate.

## Gate

`make test` + self-host byte-identical (the compiler is itself full of small
leaf functions, so the fixedpoint is a real test of this), plus
`test/lib_math_correctly_rounded.pas` under `-dPXX_FLOAT_EXACT` producing the
**same bits** at `-O2` and `-O3` — inlining must not change a result, and this
test is the sharpest available detector of that.

## Triage 2026-08-19 (Track D re-triage pass) — confirmed at the instruction level

Not just still open: **measured in the emitted code**, which is stronger than
the timing the ticket was filed on. Two identical leaves, one `Double`, one
`Integer`, compiled `-O3 -S` against the v363 pin:

```pascal
function AddD(a, b: Double): Double;   begin AddD := a + b; end;
function AddI(a, b: Integer): Integer; begin AddI := a + b; end;
```

The disassembly contains `call AddD` and **no** `call AddI` — the integer leaf
is inlined at -O3 and the float leaf is not, from the same source shape. That
is exactly the asymmetry the ticket describes, isolated to two lines.

**Genuine feature, still wanted**, and the cheapest possible repro is now on
record for whoever takes it.
