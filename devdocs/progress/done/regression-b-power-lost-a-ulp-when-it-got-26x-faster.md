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

---

## CLOSED 2026-08-16 (owner) — not a bug under the float policy; tests relaxed instead

> "this is just the exact-float. i simply don't care about minor float
> discrepancies and we should stop flagging them." — user

One factual correction that does not change the ruling: this was **not**
exact-mode-only. `-dPXX_FLOAT_EXACT` is the mode where the value is still
correct; the DEFAULT path is what moved, which is why it could turn CI red at
all. The owner's decision applies to the default path knowing that.

### What was actually red, and what was done

Both failing tests reduced to **two values, each 1 ulp from CPython** — no stale
expectations, no growing error:

| expression | CPython | pxx at HEAD |
| --- | --- | --- |
| `math.pow(2.0, 0.5)` | `1.4142135623730951` | `1.414213562373095` |
| `math.pow(1e150, 2)` | `9.999999999999999e+299` | `1e+300` |

(An earlier note here said the `1e+300` row was "stale in the GOOD direction".
That applied to `pow(1e300, 1.0)`, which is **not** in either test. Both rows
above are genuine 1-ulp gaps. Corrected.)

Per the policy — fast by default, a 1-2 ulp gap is a recorded issue and never a
bug — the defect was in the TESTS, which asserted a precision the RTL does not
promise. Those three values now print through `"%.14g"`:

- `test/test_nilpy_math_log.npy` — `pow frac` and `pow edge`
- `test/test_nilpy_math_domain_errors.npy` — the `math.pow(2, 0.5)` row

Both **GREEN**. The `.expected` files were regenerated **from CPython**, not
from pxx — the oracle is kept, it is simply not read past 14 significant
digits. Every other row in both files is untouched and still asserts CPython's
exact output.

14 rather than 15: at 15 significant digits the two `sqrt(2)` values still
round differently (`1.41421356237309` vs `1.4142135623731`), because pxx's
double sits just below the tie. 14 is the first width that is stable, and a
1-ulp double difference is invisible well before it.

### What is NOT closed

The **26x speed win stays** and the accuracy trade is now explicit rather than
accidental — which was the one thing this ticket legitimately complained about.

The diagnosis stands and is worth keeping: `FastExpHiLoCore` ends with
`Dd2Sum(1.0, <plain double expression>)`, which splits a 53-bit value into two
doubles rather than producing a 106-bit approximation, so `DdScale` has no extra
bits to round with. If anyone ever wants the ulp back, a genuine compensated
exp kernel is the fix (measured cost: reverting to the exact exp is 0.73s ->
9.44s per 1M calls, so a real hi/lo exp should land nearer 2-3x, not 13x). Not
scheduled — recorded so the next person does not re-derive it.

**Standing consequence:** stop filing 1-2 ulp findings as bugs. A test that goes
red on one is a test asserting more than the RTL promises, and the test is what
changes. Error that GROWS with the argument is still a bug — that half of the
policy is unchanged.
