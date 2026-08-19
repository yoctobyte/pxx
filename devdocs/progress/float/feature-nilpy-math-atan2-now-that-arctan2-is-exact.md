---
track: N+F
prio: 30
type: feature
blocked-by: []
summary: "compiler/pyparser.inc deliberately leaves math.atan2 undefined, with a note citing ArcTan2 being 1 ulp off CPython for atan2(0.5, 1). That reason is gone as of 2026-08-15: ArcTan2 now forms the quotient in double-double, matches CPython on that exact value, and is correctly rounded where glibc is not. One table line, plus removing the stale note."
---

# NilPy: `math.atan2` can exist now

- **Type:** feature (frontend name mapping) — **Track N** (`compiler/pyparser.inc`).
  Filed by Track B, which owns the RTL half and does not edit the Python
  frontend.
- The absence was correct when it was written; the reason it names is now
  stale.

## What the frontend says today

`compiler/pyparser.inc`, in the `math.*` dotted-name table:

> `math.atan2` is still absent, and stays absent: `ArcTan2` is 1 ulp off CPython
> for `atan2(0.5, 1)` (`0.46364760900080615` vs `...09`), so mapping it would be
> a silently wrong value in the last place. Blocked on a correctly-rounded libm,
> not on this table.

That was the right call — the name was withheld rather than shipped wrong.

## What changed

[[bug-b-rtl-math-transcendentals-lose-argument-reduction]] rewrote `ArcTan2`
over the double-double kernel. `ArcTan(y / x)` rounded the quotient before the
function started; it now forms `|y|/|x|` as a dd with the residual kept and adds
pi as a dd.

Measured after: `atan2(0.5, 1)` is `0.4636476090008061`, CPython's value to the
bit. Over 6000 random pairs, 6 differ from glibc — and on all six, 400-digit
arithmetic says **pxx is correctly rounded and glibc is not**. Signed zeros were
fixed in the same change and match FPC and CPython on all eight combinations
(`atan2(-0, -1)` is `-pi`, `atan2(-0, 1)` is `-0`).

`test/lib_math_correctly_rounded.pas` pins all of that, including the
`atan2(0.5, 1)` row the frontend note cites.

## The work

1. One line in the dotted-name table: `else if dotted = 'math.atan2' then
   Result := 'ArcTan2'`. Note it is **two-argument**, so check it lands on
   whichever path handles arity-2 stdlib calls rather than the unary one used by
   `asin`/`acos`/`atan`.
2. Delete the stale paragraph quoted above — leaving it would send the next
   reader to re-measure something already measured.
3. Argument ORDER is `atan2(y, x)` in both Python and Pascal, so there is
   nothing to swap. Assert it anyway: `math.atan2(1, 2)` is 0.4636…, not 1.107…
   — the two are only distinguishable by testing a non-symmetric pair.
4. Domain/error behaviour: CPython's `atan2` never raises (both zeros give 0.0),
   unlike `asin`, so no `pymath_dom_*` guard is needed.

## Gate

`math.atan2` rows in `test/test_nilpy_math_surface_and_random.npy` matching
CPython exactly — including a negative first argument, both signs of the second,
and `atan2(0.5, 1)` — plus `make test-nilpy` green and self-host byte-identical,
per Track N's gate.
