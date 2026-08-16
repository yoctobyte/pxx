---
track: B
prio: 65
type: regression
blocked-by: []
summary: "`11321a09c lib(B): Power and LogN, 26x each` made lib/rtl/math.pas's Power 1 ulp off CPython — `Power(2.0, 0.5)` and `Power(1e150, 2.0)` both moved. It is what turned test_nilpy_math_log and test_nilpy_math_domain_errors red in Track T's 343a52551808 cascade, and those two are still red at HEAD."
---

# `Power` lost a ulp when it got 26x faster

- **Type:** regression (accuracy, landed) — **Track B** (`lib/rtl/math.pas`).
  Filed by the Track A+C+P+N session that triaged Track T's cascade; NOT fixed
  here, because the file is Track B's lane.
- **Found:** 2026-08-16, triaging `regression-cascade-343a52551808` — three of
  its five NilPy jobs are green again at HEAD, and these two are not.

## The control (this is not a guess)

Old `math.pas` versus new, same compiler, same program:

```sh
git show 11321a09c^:lib/rtl/math.pas > /tmp/oldrtl/math.pas   # + the rest of lib/rtl copied
./compiler/pascal26 -Fulib/rtl   pw.pas pw_new    # the tree
./compiler/pascal26 -Fu/tmp/oldrtl pw.pas pw_old  # the parent of the speed commit
```

```
                     Power(2.0, 0.5)        Power(1e150, 2.0)
CPython (oracle)     1.41421356237309515    9.999999999999999e+299
OLD (11321a09c^)     1.41421356237309515    9.9999999999999990E+299     <- exact
NEW (HEAD)           1.41421356237309492    1.0000000000000001E+300     <- 1 ulp
```

`Power(3.0, 2.5)` is unchanged and exact, so this is a last-ulp error on some
inputs, not a systematically bad algorithm — the same shape as
[[bug-nilpy-float-pow-loses-a-ulp-vs-libm]], which is about a DIFFERENT
implementation (pylib's own series) and is not this.

## Why it matters more than one ulp usually does

1. **It is a landed regression with a named cause**, not a long-standing
   approximation. The commit's own claim is 26x speed; the accuracy cost was
   not part of the trade as recorded.
2. **Two tests in the tree assert the exact values** —
   `test/test_nilpy_math_log.npy` (`pow frac`, `pow edge`) and
   `test/test_nilpy_math_domain_errors.npy` — because their `.expected` files
   are CPython's output. They are RED at HEAD and are two of the seventeen jobs
   in `regression-cascade-343a52551808`.
3. **NilPy's `**` now routes here too** (`bug-a-nilpy-star-star-has-its-own-low-precision-pow`,
   6a4fa40ae, same range), on the strength of Power being measured bit-exact
   against CPython. That measurement was taken before this commit, so the
   move's premise has quietly stopped holding.

## Where to look

`11321a09c lib(B): Power and LogN, 26x each — a fast hi/lo log, and a measured
cutover`. The "fast hi/lo log" is the suspect: `Power(b, e)` computed as
`exp(e * ln b)` amplifies any error in `ln`, which is exactly why the hi/lo
split exists — so the cutover threshold, or the hi/lo recombination, is where
the lost bit is. `lib/crtl` already carries a **correctly-rounded** `pow`
(double-double; `test/cmath_pow_correct_round_b380.c`), so there is a
known-good algorithm in-tree to compare against rather than re-derive.

## Gate

`test/test_nilpy_math_log.npy` and `test/test_nilpy_math_domain_errors.npy`
diff clean against their `.expected` (CPython), the speed win is kept or the
trade is stated explicitly in the commit, and `make lib-test` green.

## DIAGNOSED 2026-08-16 (Track B, the author of 11321a09c) — it is the EXP, not the log

Both this ticket and its duplicate name the fast hi/lo **log** as the suspect.
**Measured: the log is innocent.** Isolation probe — keep `FastLogHiLo`, swap
only `FastExpHiLoCore` back to the double-double `DdExpCore`:

| | CPython | HEAD (fast log + fast exp) | probe (fast log + EXACT exp) |
| --- | --- | --- | --- |
| `Power(2.0, 0.5)` | `3FF6A09E667F3BCD` | `...BCC` **1 ulp** | `...BCD` exact |
| `Power(1e150, 2.0)` | `7E37E43C8800759B` | `...59C` **1 ulp** | `...59B` exact |
| `Power(1e300, 1.0)` | `7E37E43C8800759C` | `...59C` exact | `...59C` exact |
| `Power(3.0, 2.5)` | `402F2D4A45635640` | exact | exact |

Keeping the fast log and fixing only the exp makes every failing row exact. The
independent confirmation is the cutover: `Power(1e150, 2.0)` sits at
|y·ln x| = 690.8, **above the threshold of 16**, so it already uses `DdLogD` —
the full dd log — and was still wrong. A log that is not being called cannot be
the cause.

### The actual defect, and it is a design flaw in what I wrote

`FastExpHiLoCore` ends with

```pascal
Result := Dd2Sum(1.0, hi - (lo - (xx * c) / (2.0 - c)));
```

`Dd2Sum` splits its argument **exactly** into a hi/lo pair — but the argument
was computed in plain double arithmetic. So the result is a **53-bit value
written as two doubles, not a 106-bit approximation of e^r**. `DdScale` is then
handed no extra bits and has nothing to round with.

The log carries genuine extra precision; the exp only looks like it does. That
asymmetry is the whole bug, and the commit message's "an entry point, not a
second kernel" is exactly where the reasoning went wrong — accepting an incoming
low word is necessary but not sufficient; the kernel also has to *produce* one.

### The cost, measured — the fix is not free, and not expensive either

1M `Power` calls, same loop, `-O2`:

| configuration | time | accuracy |
| --- | --- | --- |
| fast log + fast exp (HEAD) | **0.73 s** | worst 1 ulp |
| fast log + exact exp | **9.44 s** | exact on all rows above |
| exact log + exact exp (`-dPXX_FLOAT_EXACT`, the pre-11321a09c behaviour) | **18.20 s** | correctly rounded |

So the 26x was roughly half log, half exp. Simply reverting the exp keeps only
~2x of it. **The right fix is a genuine hi/lo exp** — carry a real low word
through the polynomial (a compensated evaluation / one correction term), the
same trick that worked for the log. That should land nearer 2-3x the fast exp
than 13x, keeping most of the win. Do that, not the revert, and not a
`Power(x, 0.5) -> Sqrt` special case.

### One of the red rows is stale in the GOOD direction

Confirmed from the duplicate's finding: `Power(1e300, 1.0)` was
`9.999999999999999e+299` **before** 11321a09c and is the exact `1e+300` now, so
that `.expected` row records the old wrong value. Do not "fix" it back.
Note `pow(1e300, 1.0)` and `pow(1e150, 2.0)` are genuinely one ulp apart in
CPython too (`...59C` vs `...59B`) — they are different values, not one value
answered inconsistently.

### Duplicate merged

[[bug-b-power-lost-an-ulp-on-a-half-integer-exponent]] (B, p40) is the same
regression, filed the same day by a second triage session from the same Track T
cascade. Its unique contribution — the `1e300` row being stale-good — is folded
in above. Closing that one in favour of this.

### The policy question this exposes, which is NOT mine to settle

`decide-rtl-math-correctly-rounded-vs-fast-tier` says RTL floats are fast by
default and 1-2 ulp is a recorded issue, never a bug. But
`test/test_nilpy_math_log.npy` and `test_nilpy_math_domain_errors.npy` assert
**bit-exact CPython output**, and NilPy's contract is upward compatibility with
CPython. Since `bug-a-nilpy-star-star-has-its-own-low-precision-pow` routed `**`
here (6a4fa40ae), one function now has to serve a fast-by-default Pascal RTL and
a CPython-exact NilPy at the same time. Those are different requirements.
Collected on [[meta-float-accuracy-policy]] rather than answered here.
