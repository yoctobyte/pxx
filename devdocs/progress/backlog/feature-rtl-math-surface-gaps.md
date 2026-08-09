---
track: B
prio: 30
type: feature
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
