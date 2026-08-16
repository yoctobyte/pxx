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
