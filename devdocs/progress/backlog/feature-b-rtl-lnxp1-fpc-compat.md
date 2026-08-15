---
track: B
prio: 20
type: feature
blocked-by: []
summary: "FPC's math unit exports LnXP1(x) = ln(1+x) and pxx does not. The implementation already exists as of 2026-08-15 — LnP1, added as an internal helper for the hyperbolic family — so this is an interface line and a name, not an algorithm. Note WHY the name matters: `Log1p` would hijack libc's through pxxcio, `LnXP1` does not."
---

# `LnXP1` — FPC's ln(1+x), which we now have but do not export

- **Type:** feature (FPC compat) — **Track B** (`lib/rtl/math.pas`).
- Cheap: the function is already written.

## What exists

`LnP1(x)` was added 2026-08-15 as an implementation-only helper while fixing the
hyperbolic family ([[bug-b-tanh-returns-nan-above-709]]). It is Goldberg's
construction — `Ln(1+x) * x / ((1+x) - 1)` — accurate to ~1 ulp where the naive
`Ln(1.0 + x)` keeps none of a small x.

FPC's `rtl/objpas/math.pp` exports the same function as:

```pascal
function lnxp1(x : float) : float;
```

Delphi spells it `LnXP1` too, so the name is settled.

## Why the NAME is the whole point

Do **not** export it as `Log1p`. Every name in this unit's interface is in scope
for C name resolution, because `pxxcio` is auto-pulled into every C program and
does `uses math` — a Pascal `Log1p` would hijack libc's `log1p` in every C
program compiled by pxx. That is the documented `Pow`/`Log`/`CopySign` trap at
the top of `lib/rtl/math.pas`
([[bug-c-pascal-math-names-hijack-libc-through-pxxcio]]), and it has already
shipped broken once.

`LnXP1` is not a libc name, so it is safe. This is exactly why FPC's spelling is
the right one to adopt rather than the C one.

## The work

1. Interface declaration + a one-line body delegating to `LnP1`.
2. A `Single` overload, matching the widen/narrow pattern every other Single
   overload in the unit uses.
3. Rows in `test/lib_math_fast_tolerance.pas`: `LnXP1(1e-15)` = 1e-15 (the case
   the naive form gets wrong), `LnXP1(0)` = 0 exactly, `LnXP1(-1)` = -Inf,
   `LnXP1(x < -1)` = NaN, and a mid-range value against glibc's `log1p`.
4. Check whether an `Expm1` counterpart is wanted. FPC has **no** `expm1`
   equivalent, so there is no compat name to adopt, and the obvious C spelling
   is exactly the one that would hijack. Leave `ExpM1` internal unless a caller
   appears — and if one does, pick a non-colliding Pascal name deliberately.

## Gate

`tools/gate.sh lib` — which includes the C math tests that would catch a hijack.
