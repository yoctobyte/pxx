---
track: B
prio: 40
type: bug
blocked-by: []
summary: "The 26x Power/LogN rewrite (11321a09c) traded one ulp on a half-integer exponent: math.pow(2.0, 0.5) answers 1.414213562373095 where CPython and the correctly-rounded sqrt give 1.4142135623730951. It also FIXED math.pow(1e300, 1.0) (was 9.999999999999999e+299, now the exact 1e+300), so two frozen .expected rows in the nilpy suite are now stale in the good direction."
---

# Power lost an ulp on a half-integer exponent

Found 2026-08-16 triaging a Track T NEW-RED set at `343a52551808`. Filed from
Track A+N; the bug is Track B's (`lib/rtl` Power/LogN) — T owns the tool, never
the bug, and the same rule sends this one to the owning lane rather than to
whoever noticed.

## Measured

`test_nilpy_math_domain_errors` and `test_nilpy_math_log` reproduce identically
on the **PINNED** binary, so this is not a compiler-side change. They bisect to
`11321a09c lib(B): Power and LogN, 26x each`.

| expression | CPython 3 | pxx now | pxx before |
| --- | --- | --- | --- |
| `math.pow(2.0, 0.5)` | `1.4142135623730951` | `1.414213562373095` | `1.4142135623730951` |
| `math.pow(1e300, 1.0)` | `1e+300` | `1e+300` | `9.999999999999999e+299` |

So the rewrite is a net improvement that costs one ulp on the half-integer
exponent, and the two red rows are one regression plus one fixed row whose
`.expected` still records the old wrong value.

## Shape of the fix

`x ** 0.5` is `sqrt(x)` exactly, and this RTL already has a correctly-rounded
sqrt. The generic `exp(y * ln x)` path cannot hold the last bit, which is why
CPython (and libm) special-case the half-integer exponents before reaching it.
Special-case `y = 0.5` (and `-0.5` → `1/sqrt(x)`) at the top of `Power`, keeping
the fast general path for everything else.

## Also do

Re-record the `1e300` row: `test/test_nilpy_math_log.expected` line 18 still
says `9.999999999999999e+299`, which is the value the rewrite CORRECTLY stopped
producing. Do that in the same commit as the ulp fix so the suite goes green in
one step rather than through a half-green state.

Related: [[feedback_float_handling_bugs_are_low_prio_track_b]] — accuracy work is
mechanical Track B, hence prio 40 rather than higher, even though it is currently
holding two suite rows red.
