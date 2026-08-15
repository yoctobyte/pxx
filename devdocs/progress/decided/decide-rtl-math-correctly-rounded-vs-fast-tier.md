---
track: U
prio: 35
type: decide
blocked-by: []
summary: "lib/rtl/math.pas's transcendentals are correctly rounded and ~1000x slower than libm — MEASURED: Ln+Exp 16,480 ms per 1M pairs against glibc's 13 ms, and the new dd Sin/Cos 29,383 ms against a plain-double 673 ms. That is the SHIPPED standard today, not a proposal. Question: is one correctly-rounded tier the intended answer for a language whose demos draw graphics, or does the RTL want a fast tier alongside it? Three options, recommendation inside."
status: decided
---

# Decide: does the RTL math want a FAST tier next to the correct one?

- **Type:** decide (Track U — design/policy, not work) — surfaced by Track B on
  2026-08-15 while landing
  [[bug-b-rtl-math-transcendentals-lose-argument-reduction]].
- **Nothing is blocked on this.** The correctness fixes are landed and green.
  This asks whether the resulting *cost* is the intended trade, because the
  answer changes what the next several math tickets should do.

## The measurement, which is what makes this a question

Same box, `-O2`, 1M iterations each:

| | pxx RTL | glibc | ratio |
| --- | --- | --- | --- |
| `Ln` + `Exp` (dd, correctly rounded — **shipped, blessed**) | 16,480 ms | 13 ms | **1270x** |
| `Sin` + `Cos` (dd, this week) | 29,383 ms | ~660 ms | **44x** vs the old broken one |
| the SAME dd algorithm through pxx's C frontend (`lib/crtl`) | 41,174 ms | — | — |
| `Sqrt` before `sqrtsd` | 575 ms | — | — |
| `Sqrt` now (`sqrtsd`, x86-64) | 18 ms | — | — |

Two things that measurement settles, and they matter:

- **It is not a codegen problem.** The identical algorithm compiled through the
  C frontend is *slower* (41 s) than the Pascal port (29 s), so this is the
  price of the algorithm, not of Pascal or of pxx's code generation.
- **The bill was already being paid before this week.** `Ln`/`Exp` have shipped
  at 1270x for months, enforced by `test/lib_math_correctly_rounded.pas`. The
  new `Sin`/`Cos` are *consistent with* that standard, not a departure from it —
  which is exactly why one agent should not quietly pick a different policy for
  one function.

## Why it might not matter, and why it might

**Might not:** nothing in this tree calls trig per-pixel. `lib/rtl/vecmath`
uses `Sin`/`Cos` to build a rotation matrix (once per matrix), and
`examples/raytracer`, `examples/gl/triangle` use them for camera and animation
angles (once per frame). At 29 us a call that is invisible inside a 16 ms
frame. The `make demos` timings will say whether that holds.

**Might:** the north star is compiling real-world code as-is
([[frank2-mission-compile-real-world-asis]] in spirit). Real-world numerical
code *does* call `sin`/`exp` in inner loops — a DSP filter, an FFT twiddle
table, a physics step, anything ported from C that assumed libm's ~50 ns. Such
a program does not fail, it just runs 1000x slower than the C it came from, and
the reason is invisible from the source. That is the same class of problem as a
wrong answer being invisible: the user cannot see it without a profiler.

## The options

1. **Keep one tier: correctly rounded, slow.** Zero work, zero surface, and the
   answer is never wrong. Anyone who needs speed calls into `lib/crtl` — except
   that is slower still, so really they have nowhere to go.
2. **Add a fast tier alongside** — `FastSin`/`FastExp`/... or a unit-level
   `{$define PXX_FAST_MATH}` — implemented with fdlibm-style plain-double
   polynomial kernels on top of the dd *reduction* that just landed. About 1 ulp
   instead of 0, at roughly libm speed. The reduction is where the billions of
   ulp came from and it is cheap; the dd *kernel* is where the 1000x goes.
3. **Flip the default to fast (~1 ulp) and keep the correct one under a name.**
   What libm itself does. Costs the current guarantee, and would need
   `lib_math_correctly_rounded` rewritten around a tolerance — losing the
   property that test exists to hold.

## Recommendation

**Option 2.** It keeps the guarantee that is already shipped and tested, it
gives the numerical-code case somewhere to go, and the expensive half of the
work is already done — the double-double reduction landed this week, and a fast
kernel bolts onto it. Option 3 trades away a real, tested property for speed
most callers here do not need; option 1 leaves a real gap with no answer.

If option 2 is chosen, the follow-up is a Track B ticket: fdlibm `__kernel_sin`
/ `__kernel_cos` polynomials in plain double, taking the reduced argument's head
AND tail from the existing `TrigReduce`, plus the equivalent for `Exp`/`Ln`.

## What is NOT being asked

Whether the correctness fixes were right — they were, and the same sweep shows
pxx is now correctly rounded where **glibc is not** (sin 3, cos 2, tan 6 wrong
out of 337 against 400-digit arithmetic; asin/acos 7 of 3000). This ticket is
only about whether a second, faster tier should exist beside them.

---

## DECIDED 2026-08-15 — fast by default, exact behind a flag

The user's ruling, verbatim:

> *"i have the belly full of those floating point issues. so here is the plan. we
> make a mode --strict-float. if that is set, we mimic the exact outcome. default
> would be like 'fast float' where we really dont care the last insignificant
> bit(s). this is not the first time, and we are wasting time on hunting
> something that simply is not an issue. ... so - default is fast floats (as fast
> as we can). if a testing lib insists on slow(er) but more accurate floats -
> sure. it would also mean any minor divergion is no longer a bug, just a
> recorded issue."*

Two clarifications he attached, both worth keeping because both are easy to get
wrong:

- The accuracy work that produced this question was **not** wasted — it fixed
  real wrong VALUES. What is dropped is the last-bit *guarantee*, not the fixes.
- **"Fast" is not `-ffast-math`.** Nothing moves to `Single`, nothing reassociates,
  nothing flushes to zero. Still IEEE double throughout.

Also settled by measurement, against two pieces of folklore raised in the
question: there is no usable hardware trig on the targets that matter (x87's
`fsin` is slower AND less accurate; x86-64 SSE and aarch64 have none), and
80-bit extended buys 11 bits where double-double buys 53. `sqrtsd`/`fsqrt` IS
exact hardware and is used.

**The policy now lives in `devdocs/dev/float-policy.md`** — that file, not this
ticket, is what to read before filing or "fixing" a float-accuracy issue.

### Landed with the decision

- `Sin`/`Cos`/`Tan` fast by default: **261 ms** per 1M sin+cos, down from
  31,828 ms — 122x — at ~1 ulp (`Tan` 2 ulp) over 8,204 arguments.
- `-dPXX_FLOAT_EXACT` selects the double-double path.
  `test/lib_math_correctly_rounded.pas` is built with it in the Makefile.
- `test/lib_math_fast_tolerance.pas` (new) tests the default path: accuracy as a
  2-ulp TOLERANCE, behaviour (signed zeros, NaN, Inf, reduction out to 1e100)
  asserted EXACTLY. Green on x86-64, i386, aarch64, arm32, riscv32.

### Deliberately left open

- **The flag NAME.** The user said "strict float" is probably the wrong name and
  did not pick a replacement. What exists today is the conditional define
  `-dPXX_FLOAT_EXACT`; a driver-level spelling (`--float=exact`?) is a Track A
  change and is not filed yet, on purpose — name it first.
- **`Ln`/`Exp` are still exact-only**, and they are the *worse* ratio (1270x).
  [[feature-b-rtl-fast-ln-exp-path]].

## Log
- 2026-08-15 — decided, commit 4df34a186.
