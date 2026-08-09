---
track: B
prio: 30
type: feature
status: done
owner: claude-B
---

# `math` surface gaps — 16 names missing, all LOUD

Measured against CPython by calling each name; every one below fails to compile
with `undefined variable (...)`, so none can produce a wrong answer. That is why
this is one low-priority ticket rather than sixteen.

**Missing:** `trunc`, `e`, `pow`, `log(x, base)` (the two-argument form —
`log10`/`log2` exist), `atan2`, `factorial`, `isnan`, `isinf`, `degrees`,
`radians`, `inf`, `nan`, `tau`, `copysign`, `isclose`, `comb`, `prod`.

**Present and correct:** `pi`, `sqrt`, `sin`, `cos`, `gcd`, `fabs`, `hypot`,
`fmod`, `floor`, `ceil`, `log2`, `exp` (1 ulp — see the log10 ticket).

Notes on a few that are not just aliases:

- `isnan` / `isinf` are the ones real code most often needs, because without
  them a NaN can only be detected by the `x != x` trick.
- `inf` / `nan` as CONSTANTS pair with them; `float("inf")` already works, so
  these are spellings of a value that exists.
- `trunc` differs from `floor` for negatives (`trunc(-2.5)` is -2, `floor` is
  -3) — a plausible-looking wrong substitution, so implement it rather than
  aliasing.
- `pow(x, y)` must be the FLOAT contract (always a float), unlike the `**`
  operator's int-preserving one.
- `log(x, base)` is the two-argument form; `LogN` already exists in
  `lib/rtl/math.pas` under that name.

## Gate

`make lib-test` + a CPython-diffed test calling each name, including
`trunc`/`floor` on negatives, `isnan`/`isinf` on the three special values, and
`log(x, base)` against `log10`/`log2` for agreement.

## Resolution 2026-08-09 (Track B) — 12 in the RTL, 4 escalated

NilPy's `import math` resolves ordinary names case-insensitively against
`lib/rtl/math.pas`, so fourteen of these are RTL additions and now match CPython
exactly, verified by diffing a `.npy` against `python3` until identical:

`e`, `tau`, `inf`, `nan`, `isnan`, `isinf`, `atan2`, `degrees`, `radians`,
`isclose`, `factorial`, `comb` — twelve. (`prod` takes an iterable and is
Python-shaped rather than a math gap, so it is not here.)

Three things measurement changed:

**`inf`/`nan` cannot be built from `1.0/0.0`.** The obvious form raises
ZeroDivisionError the moment a NilPy program says `math.inf` — the check fires
inside the RTL function. They are IEEE bit patterns now (the Sqrt seed's
reinterpret trick), which is exact by construction anyway. `copysign` had the
same problem for the opposite reason: the `1.0/y` idiom is the only way a
COMPARISON can see -0.0, so it reads the sign bit instead.

**`trunc` is deliberately NOT added**, and that is the opposite of the ticket's
instruction to implement rather than alias. Python's returns an INT; a
`Double->Double Trunc` in the math unit resolves ahead of everything and answers
`-2.0` where CPython says `-2`, quietly. That is the same int-contract mismatch
that made `math.floor`/`math.ceil` frontend intercepts, so it wants a
`pymath_trunc` beside them — an honest `undefined variable (trunc)` is better
than a wrong type in the meantime.

**`pow`, `log` and `copysign` could not go in this unit at all**, and finding
out cost a RED gate on a C test that had nothing to do with the change.
`pxxcio` is auto-pulled into every C program and does `uses math`, so every name
in `lib/rtl/math.pas` is in scope for C name resolution, case-insensitively — a
Pascal `Pow` made a C program's `pow(2,10)` answer **1** instead of 1024, and
`CopySign` made `copysign(3,-1)` answer **0.785398**, which is `atan2(1,1)`.
Silently. `lib/crtl/src/math.c` already documents the hazard from the other side
(it renamed its own functions `__crtl_log2`/`__crtl_log10` to dodge it); nothing
protected this direction. Filed as
[[bug-c-pascal-math-names-hijack-libc-through-pxxcio]] with `prio: 55`, since the
trigger is an ordinary Track B edit and the symptom is a silent wrong answer in
unrelated code. `test/cmath_no_pascal_hijack.c` is now a canary for it in
`lib-test`.

**`log(x, base)` had a SECOND reason to stay out.** Measured, all three:

| | `log(1000, 10)` |
| --- | --- |
| CPython | `2.9999999999999996` |
| FPC `LogN(10, 1000)` | `3.0` |
| pxx `LogN` | `3.0` |

CPython does not snap; FPC does; we match FPC. Neither is wrong — each matches
its own oracle — so `LogN` stays FPC-faithful and NilPy needs its own intercept.
Note the argument order differs too (`log(x, base)` vs `LogN(base, x)`), which
is a silent-wrong-answer shape, so both spellings now exist and each is correct
under its own name.

All four (`pow`, `log`, `copysign`, `trunc`) escalated as
[[bug-n-math-trunc-and-log-need-frontend-intercepts]] — they want NilPy
intercepts, which is also the only route that survives the hijack bug.

One divergence left that is NOT in scope here: `math.pow(2.0, 0.5)` is 3 ulp off
CPython, because `Power` rides `Exp`/`Ln` —
[[feature-rtl-ln-exp-are-a-ulp-off-port-the-crtl-dd-core]] is the root cause and
already filed.

Regression test: `test/lib_math_python_surface.pas`, in `make lib-test`.


## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
