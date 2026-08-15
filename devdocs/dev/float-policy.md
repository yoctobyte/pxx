# Float policy — fast by default, exact on request

**User decision, 2026-08-15.** Read this before filing, claiming, or "fixing"
anything about floating-point accuracy.

## What "fast" does NOT mean

Say this first, because the phrase is loaded. This is **not** gcc's
`-ffast-math`, and nothing below trades away a property a program can observe:

- **Still IEEE double throughout.** Nothing moves to Single, nothing computes at
  reduced width, no result loses precision beyond its last bit or two.
- **No reassociation, no "assume finite", no flush-to-zero.** Denormals stay
  denormal, NaN stays NaN, infinities propagate, signed zeros keep their sign.
  Those are behaviour, not accuracy, and they remain exact in both modes.
- **Argument reduction stays exact.** `Sin(1e10)` answering an uncorrelated
  number was a real bug and its fix is in the fast path too. An error that
  GROWS with the argument is never acceptable in either mode.
- **Special values stay exact.** `Sqrt(-0)` is `-0`, `ArcTan2(-0, -1)` is `-pi`,
  `Cos(0)` is exactly 1.

The only thing given up is the guarantee that the last bit is the
correctly-rounded one, in exchange for not paying a wildly disproportionate
price for it.

## The rule

1. **The default is FAST.** `lib/rtl/math.pas` aims at libm's speed and libm's
   accuracy class (~1 ulp) — the same contract every other language's standard
   library offers. It does not aim at the correctly-rounded result.
2. **`-dPXX_FLOAT_EXACT` selects the exact path** — the double-double kernels,
   correctly rounded, ~1000x slower. For test libraries and for anything that
   genuinely needs a reproducible last bit.
3. **A last-bit divergence is NOT A BUG.** It is a recorded issue at most. Do
   not file it as `bug-`, do not claim a ticket for it, do not spend a session
   arbitrating it against 400-digit arithmetic.

## What IS still a bug

The distinction is *size*, not *kind*:

| symptom | verdict |
| --- | --- |
| 1-2 ulp off glibc/CPython | **not a bug.** Record it in this file's table if it is worth remembering at all. |
| a few ulp, growing with the argument | **look once** — that is usually a reduction defect wearing a small number. |
| 85 ulp at x=100, 1.2 million at 1e6 | **bug.** That was `Sin` before the reduction port, and it was real. |
| wrong magnitude, NaN, Inf, a lost sign, a denormal answered as zero | **bug**, always. |
| `Trunc`/`Int`/`Floor` giving the wrong INTEGER | **bug**, always — that is not float accuracy, it is a wrong value. |

The line: **does the error stay bounded and tiny across the whole domain, or
does it grow?** A bounded 1-2 ulp is the cost of doing arithmetic in 53 bits.
An error that grows with the argument means a step of the algorithm is wrong,
and that is worth fixing regardless of how small it looks at x = 0.5.

## Why (the measurements behind the decision)

Per 1M calls, this box, `-O2`:

| | pxx (dd, correctly rounded) | glibc | ratio |
| --- | --- | --- | --- |
| `Ln` + `Exp` | 16,480 ms | 13 ms | **1270x** |
| `Sin` + `Cos` | 29,383 ms | ~660 ms | 44x |

And per `sin` kernel call, the same arithmetic three ways:

| | time | accuracy |
| --- | --- | --- |
| dd Taylor over the dd primitives | 7.96 us | correctly rounded |
| identical arithmetic, hand-inlined | 2.11 us | correctly rounded (bit-identical) |
| plain-double minimax kernel | **0.029 us** | ~1 ulp |

275x, for a difference nobody's program can observe.

**What the fast path actually delivers**, measured after the switch (same box,
1M `Sin` + `Cos`, `-O2`):

| | time | worst error over 8,204 arguments |
| --- | --- | --- |
| default (fdlibm minimax kernels) | **261 ms** | `Sin` 1 ulp, `Cos` 1 ulp, `Tan` 2 ulp |
| `-dPXX_FLOAT_EXACT` (double-double) | 31,828 ms | correctly rounded |

122x, and the two agree on every digit any program prints. The reduction is
shared, so `Sin(1e100)` is within 2 ulp in **both** columns.

**The accuracy work that got us here was not wasted** — it found and fixed real
defects: `Sqrt` returning `-Inf` just below DBL_MAX, `ArcCos` 1099 ulp out from
a cancelling subtraction, `Sin` uncorrelated with the truth past 1e10, `Int()`
saturating to 32 bits on two backends, `ArcTan2` losing signed zeros. Every one
of those is a wrong VALUE and every one stays fixed.

What changed is narrower: the correctly-rounded *guarantee* is not worth its
price. It was never a product decision anyway — it arrived because
double-double happened to be the convenient way to fix a real 1-ulp `Log10`
bug, and then it set a bar every later function had to clear.

## What other implementations actually do

Worth stating, because the folklore is wrong in two specific ways:

- **There is no *usable* hardware trig on the targets that matter.** x87 has
  `fsin`, `fcos`, `fptan`, `fpatan` and every x86-64 CPU still has them, but
  x86-64's SSE has no equivalent, aarch64 and riscv have none, and the x87 ones
  fail on accuracy. **Measured on this box, 1M calls** (`gcc -O2`, `fsin` via
  inline asm):

  | | time | `sin(1e10)` |
  | --- | --- | --- |
  | x87 `fsin` | 34 ms | **~202,000 ulp wrong** |
  | glibc `sin` | **7 ms** | correct |
  | pxx `Sin` (fast path) | 117 ms | correct |

  `fsin`'s argument reduction uses a **66-bit pi**, so it degrades exactly where
  ours used to: error grows with the argument. Past 2^63 it does not even try —
  `fsin(1e22)` returns `1e22`, the input, with C2 set. Intel's manual claimed
  ~1 ulp for two decades and was corrected in 2014 to admit errors up to ~1.3
  quintillion ulp near multiples of pi. Adopting it would reintroduce the class
  of bug this file exists to keep fixed.

  Note the honest half: `fsin` is currently **3x faster than our own fast
  path**, so "it is slow" is only true relative to a *good* polynomial — glibc's
  is good and beats it 5x. Ours is not there yet (see the headroom note below).
  The reason to refuse `fsin` is accuracy and portability, not speed.

  The one real hardware win is `sqrtsd` / `fsqrt`, which IS exact and IS used here.

- **We are still ~17x off glibc on `Sin`** (131 ms vs 7 ms per 1M), and it is
  **not the polynomial** — the identical algorithm compiled by `gcc -O2
  -mno-fma`, same instruction set, runs in 9 ms. Decomposed:

  | | | |
  | --- | --- | --- |
  | computing `cos` when only `sin` is wanted | 1.5x | ours to fix, `lib/rtl` |
  | call overhead (hand-inlining everything) | 1.2x | [[feature-opt-inline-float-and-record-returning-leaves]] |
  | **the x86-64 float value model** | **7.2x** | [[feature-opt-float-register-temporaries]] |
  | glibc's extra fast paths over ours | 1.3x | — |

  The 7.2x is the one that matters and it is a known, deliberately parked Track O
  ticket: a Double is carried as raw bits in RAX, so every operation costs three
  GPR<->XMM transfers plus a stack round-trip. One hand-inlined `Sin` emits 811
  instructions for 80 float operations, including 316 `movq` — gcc emits 61
  instructions and zero `movq` for the same source.

  **FMA is a red herring here**: allowing it in the gcc build moved 15 ms to
  12 ms, ~20%. Worth having eventually; not the gap.

  None of this is an accuracy question, and none of it is `lib/rtl`'s to fix
  beyond the first row.
- **80-bit extended is not the trick either.** It buys 11 bits; double-double
  buys 53, and costs the same order of magnitude. It is also unavailable in the
  x86-64 ABI's SSE registers and absent on ARM.

What libm actually does is **minimax polynomials instead of Taylor** (a third
of the terms, no divisions), sometimes with a small lookup table, and careful
argument reduction only where the argument is large. That is what the fast path
here does.

## Consequences for the codebase

- `test/lib_math_correctly_rounded.pas` tests the **exact** path and is built
  with `-dPXX_FLOAT_EXACT`. Its "glibc is wrong here" rows stay meaningful
  because that mode really is correctly rounded.
- The default path gets a tolerance test instead: within a stated ulp bound of
  glibc, plus every special value (zeros with sign, infinities, NaN) exact —
  because those are not accuracy, they are behaviour.
- **Reduction stays exact in both modes.** `Sin(1e10)` being uncorrelated with
  the truth was never a rounding question; the Cody-Waite / Payne-Hanek
  reduction is in the fast path too.
- **Cross-verify a new float path on every target, not just x86-64.** The lib
  gate is x86-64 only, and the fast trig path shipped a *segfault* on i386 the
  first time round — `var sn, cs: Double` out-parameters, which turn out to fault
  on any access there
  ([[bug-a-i386-var-float-parameter-faults-on-first-access]]). One qemu run per
  target caught it; nothing in the x86-64 gate could have.
- **`Ln`/`Exp` have NOT been converted yet.** They are the 1270x row above and
  still run the double-double path unconditionally. Same treatment is owed:
  [[feature-b-rtl-fast-ln-exp-path]].

## Recorded divergences (not bugs)

| where | divergence | note |
| --- | --- | --- |
| `Log10` | up to 1 ulp from glibc | in EXACT mode we are the correct one; glibc's log10 is not correctly rounded |
| `ArcSin`/`ArcCos`/`Sin`/`Cos`/`Tan`/`ArcTan2` | up to 1 ulp from glibc in exact mode | measured against 400-digit arithmetic: ours is the correctly-rounded value on every disputed case |
| default (fast) mode | up to ~2 ulp from glibc | by design; see the rule above |
