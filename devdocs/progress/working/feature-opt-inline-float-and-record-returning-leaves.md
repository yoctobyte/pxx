---
track: A
prio: 45
type: feature
blocked-by: []
summary: "FLOAT HALF LANDED at -O3 (InlineScalarTk widened to tySingle/tyDouble + an AN_FLOAT_LIT arm); -O0/-O1/-O2 byte-identical on compiler.pas. Measured 2.7x on a float-leaf microbench and 1.18x on a 10M-iteration math-unit workload. The RECORD HALF IS NOT DONE and is where this ticket's headline 3.8x actually lives: the dd kernels it was measured on (DdMul/DdAdd/Dd2Sum/Dd2Prod/DdFast2Sum) all return TDd, a RECORD of two Doubles, so the float change does not touch them. Admitting floats also opened the float arm of the dropped-narrowing bug fixed in 191af3440 (D2S returned the full Double, I2S(16777217) returned 16777217) -- guarded here by routing any conversion into a float result to shape 3."
status: working
owner: frank-optimize
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


## 2026-09-04 (frank-optimize) — the float half landed at -O3; the RECORD half is untouched and holds the headline

**The ticket's open question is answered, by measurement rather than by reading.**
"Deliberate ABI-return-slot restriction, or just where the implementation
stopped?" — it stopped. The whole restriction was one four-line predicate,
`InlineScalarTk` in `compiler/inline_expand.inc`, whose accepted set ends at
`tyPointer` (17) with the floats sitting at 18/19/20 immediately after it.
Widening it self-hosts on the first try.

### What landed

- `InlineScalarTk` accepts `tySingle`/`tyDouble` **when `OptLevel >= 3`**, per the
  Track O charter. `tyExtended` deliberately stays out: 10-byte x87 with its own
  load/store path, not an SSE2 register scalar.
- An `AN_FLOAT_LIT` arm in `InlineExprSimple`, same `-O3` gate. Without it the
  change was nearly pointless — `Sq := x * x` inlined while `Mix := a * 0.5 + b * 0.25`
  declined, and coefficients are what numeric kernels are *made of*.
- The stale doc comment above `InlineExprSimple` ("Rejects ... managed/float")
  corrected in the same commit.

### A miscompile this opened, found and fixed here

Admitting floats opened the **float arm of the dropped-narrowing bug fixed in
191af3440**. Shape 1 retains the RHS and drops the assignment, and the store is
where the narrowing lives. The existing guard tests `TypeIsOrdinal` on BOTH
sides, so it could not see it. Measured at -O3, all correct at -O0/-O2 and
correct out-of-line:

| | -O3 before the guard | correct |
| --- | --- | --- |
| `D2S(1/3)` into a Double | 0.33333333333333331 | 0.33333334326744080 |
| `I2S(16777217)` | 16777217 | 16777216 |

Fixed by routing **any** RHS whose kind is not already the float result kind to
shape 3, which stores through a properly typed Result temp — one condition, not
a second predicate that distinguishes narrowing from widening
(`normalise-dont-special-case`). `NarrowD` still inlines afterwards, via shape 3
rather than shape 1, so the guard costs correctness nothing and value nothing.

### Promise — delivered value, measured, control vs mine, min-of-N interleaved

Control `1968c7a7da57` (stock HEAD, confirmed byte-identical to the `make`-built
binary) against the change. Two distinct sha256s, printed.

| workload | control | mine | |
| --- | --- | --- | --- |
| float-leaf microbench, 20M iters | 0.49 s | 0.18 s | **2.72x** |
| math unit (`Sqrt`+`Sin`+`Ln`), 10M iters | 3.65 s | 3.10 s | **1.18x** |

The second is the honest one. On that program the change removes **8 of 206
calls** (7x `Abs`, 1x `FastSinK`); `Sin`/`Sqrt`/`Ln` themselves are retained but
decline at the call site, which is not yet explained and is the obvious next
thread.

### THE HEADLINE 3.8x IS THE RECORD HALF, AND IT IS NOT IMPLEMENTED

`DdMul`, `DdAdd`, `DdAddD`, `DdMulD`, `Dd2Sum`, `Dd2Prod`, `DdFast2Sum`,
`DdDiv`, `DdDivD`, `DdSqrt` all return **`TDd = record Hi, Lo: Double end`**.
Only `DdBits` returns a plain `Double`. So the sin-kernel measurement this
ticket was filed on belongs entirely to the record half, and **nothing in this
commit moves it.** Do not read the 1.18x as a refutation of the 3.8x, and do not
read the 3.8x as delivered. They are different halves of the same ticket.

### Safety, and a gap in the net that is worth its own ticket

- `-O0`/`-O1`/`-O2` **byte-identical** on `compiler/compiler.pas` (~4150 procs),
  control vs mine, same source tree both sides.
- Self-host fixedpoint: `converged after 1 round(s)` on every build.
- The ticket's own named gate, `test/lib_math_correctly_rounded.pas` under
  `-dPXX_FLOAT_EXACT`, agrees -O0/-O2/-O3 — but its whole output is one line
  (`MATHROUND OK`), so it is a much weaker detector than "same bits" suggests.
  Its value here is that the probe shows float routines really are retained in
  that compile, so it is at least reaching the new code.
- **`tools/optfuzz.sh` cannot see this feature at all.** `pasmith.py` has no
  float generation — zero `Double`/`Single` declarations across five seeds at
  optfuzz's own flags, and no `--floats` knob exists; its 28 "float" hits are
  prose and one `argparse type=float`. So the harness that exists *specifically*
  because curated gates missed 21 silent -O3 inliner divergences is structurally
  blind to float inlining. Running it here proves the **integer** path is
  unregressed and nothing about the new surface. Filed separately.

### Proof — stated as blocked, not as passed

Track O's PROOF gate is Track T's full tier. Not attainable right now: the
sweeping host cannot produce `skip_holes == 0` (no RDRAND, open `decide-`), and
has produced 308 full-tier reports with zero GREEN. So this is **promise
measured, proof outstanding**, and it stays at `-O3` — which is where the
charter puts an unproven pass anyway. No promotion is requested.

### The regression test, and its positive control

`test/test_inline_float_result_narrows.pas`, wired at **-O0 and -O3** (an -O2-only
arm cannot catch this, because floats are not admitted below -O3). It is the
float sibling of `test_inline_result_narrows` and mirrors its structure,
including the four rows that must NOT change — widening and same-kind cases that
still take shape 1, so a future guard cannot pass by disabling float inlining
altogether.

**Proven to fail on the broken binary**, which is the part that makes it a test:
compiled with the pre-guard compiler `df2318a5f745` it prints
`0.33333333333333331` and `16777217.0` on the first four rows and the correct
values on the last four; with `c6d5ab1a3edb` all eight are correct at both -O0
and -O3.

### A separate float differential, run but not landed as a test

14 shapes (Single/Double leaves, a Horner chain, every conversion direction, a
ternary, a multi-statement body with a float local, a global read, a non-leaf
wrapper, argument evaluation order, a Boolean-returning float comparison, and
recursion) agree across -O0/-O1/-O2/-O3 and match the stock compiler's -O3
output exactly. 12 of the 13 routines verifiably inline at -O3; `Recur` stays a
real call, which is the recursion guard behaving. Kept in the session scratchpad
rather than landed, because `test_inline_float_result_narrows` covers the arm
that actually broke and the rest duplicates `test_inline_expand`'s job.
