---
track: N
prio: 35
type: bug
summary: "math.trunc must return an int like CPython; math.log(x, base) must be CPython's unsnapped quotient rather than the FPC-faithful LogN; and math.pow/math.copysign cannot be RTL names at all because they hijack libc in every C program"
---

# `math.trunc`, `math.log(x, base)`, `math.pow`, `math.copysign` and `math.atan2` need `pymath_*` intercepts

- **Type:** bug — Track N (`compiler/pyparser.inc`, the `PyStdlibCallProc` table)
- **Opened:** 2026-08-09
- **Filed by:** Track B, doing [[feature-rtl-math-surface-gaps]]. Twelve of the
  sixteen missing names went into `lib/rtl/math.pas` and now match CPython
  exactly. These four cannot: `trunc` and `log` are CONTRACT mismatches — the
  same shape as `math.floor` / `math.ceil`, which already have intercepts a few
  lines above where these belong — and `pow` / `copysign` are blocked by a
  NAME-RESOLUTION bug (section 3).

## 1. `math.trunc` returns a float

CPython:

    math.trunc(-2.5)  ->  -2      (an int)

A Pascal `Trunc(x: Double): Double` in the math unit answers `-2.0`, and the
Python-visible difference is the TYPE, not the value. That is exactly why
`math.floor` and `math.ceil` are intercepted as `pymath_floor` / `pymath_ceil`
rather than resolved against the RTL:

> `math.floor`/`math.ceil` must NOT reach the RTL Math unit's own Floor/Ceil
> (Double->Double, correct for the Pascal frontend, wrong for Python's int
> contract)

`math.trunc` wants `pymath_trunc` beside them, rounding TOWARD ZERO (which is
`floor` only for positives — `trunc(-2.5)` is -2 where `floor(-2.5)` is -3).
Deliberately NOT added to `lib/rtl/math.pas`: a Double->Double `Trunc` there
would resolve ahead of everything and hand every caller the wrong type quietly,
which is worse than the current honest `undefined variable (trunc)`.

## 2. `math.log(x, base)` — the two oracles genuinely disagree

Measured 2026-08-09, all three on this box:

| | `log(1000, 10)` |
| --- | --- |
| CPython `math.log(1000, 10)` | `2.9999999999999996` |
| FPC `LogN(10, 1000)` | `3.00000000000000000` |
| pxx `LogN` (after [[bug-rtl-log10-is-inexact-for-powers-of-ten]]) | `3.0` |

CPython computes `log(x)/log(base)` as a plain quotient and does not snap;
FPC's `LogN` lands exactly on the integer, and pxx's now matches FPC. Note the
argument order differs too (`log(x, base)` vs `LogN(base, x)`), so `math.log`
already needs a shim of some kind.

**Neither implementation is wrong** — each matches its own language's oracle.
That is what an intercept is for: keep `LogN` FPC-faithful for the Pascal
frontend, and give NilPy a `pymath_log` computing CPython's unsnapped quotient.
`math.log10` and `math.log2` need nothing — CPython and FPC agree there, both
exact, and pxx matches both.

Filed as a bug rather than a Track U question because the NilPy rule settles it:
upward compatibility is about a program CPython *accepts and runs*, and ordinary
code branches on this value (`int(math.log(n, 10))` differs by one) — the same
test `devdocs/dev/nilpy-semantics-divergences.md` applies to
`isinstance(t, list)`.

## 3. `pow`, `copysign` and `atan2` cannot live in the Pascal RTL either

Added there, they hijack libc's in every C program —
[[bug-c-pascal-math-names-hijack-libc-through-pxxcio]], measured: `pow(2,10)`
answered 1, `copysign(3,-1)` answered atan2's result, and `atan2(0.5,1)`
answered `atan2(1,1)`. So even though they are
plain float functions with no contract mismatch, an intercept is the only route
that works until that bug is fixed. `Power` and the sign-bit logic are already
in `lib/rtl/math.pas` under non-colliding names for the intercepts to call.

## Gate

`make test-nilpy` green + a `.npy` test whose expectation is CPython's own
output for `math.trunc` on negatives and `math.log(1000, 10)` /
`math.log(8, 2)`.

## 2026-08-11 — `trunc` and `copysign` LANDED; `log`/`pow`/`atan2` blocked, measured

Two of the five are done and shipped as `pymath_trunc` / `pymath_copysign`
intercepts beside `pymath_floor`/`pymath_ceil`, exactly where section 1 says
they belong. Both were loud `undefined variable` compile errors before, so
nothing silently changed behaviour.

- **`math.trunc`** returns `Int64`, so the int contract holds. Rounds toward
  zero, which is floor only for positives — both `trunc(-2.5) = -2` and
  `floor(-2.5) = -3` are in the test.
- **`math.copysign`** reads the sign from `y`'s **bit pattern** rather than
  `y < 0`. That matters for one row: CPython's `copysign(3, -0.0)` is `-3.0`,
  and a comparison answers `+3.0` because negative zero compares equal to zero.

Test rows added to `test_nilpy_math_floor_ceil_int.npy` (the arm's own test),
expectations taken from CPython.

### Why the other three did NOT land — a builtin unit has no transcendentals

This is the fact the ticket does not record, and it changes the shape of the
remaining work. `pylib.pas` is a **builtin** unit. Adding `Ln` to it fails to
compile:

```
pascal26:4680: error: undefined variable (Ln)
```

`Ln` lives in `lib/rtl/math.pas`, a library unit. So `pymath_log` cannot simply
be `Ln(x) / Ln(base)` the way section 2 assumes — there is no `Ln` to call.

Two routes remain, neither a one-liner:

1. **`uses math` in pylib.** It is *permitted* — pylib already uses `typinfo`,
   which is `lib/rtl/typinfo.pas` — but `lib/rtl/math.pas` exports `Min`, `Max`
   and `Power`, and pylib defines its own `min`/`max` overloads. That is the
   recorded "builtin overload COMPETES with a used-unit routine, and argument
   width steers" hazard, i.e. a silent re-resolution of `min`/`max` for every
   NilPy program. Not worth it for `log` without measuring that fallout.
2. **A frontend lowering** that emits `Ln(x) / Ln(base)` against the RTL's `Ln`
   as an AST division of two calls, rather than a pylib shim. This keeps the
   builtin unit out of it entirely and is probably the right answer, but it is
   not a shim-table entry — the table maps a dotted name to ONE pylib proc.

Note the arity question is already solved either way: `PyParseStdlibCall`
re-targets by arity through `FindProcArity`, so a 1-arg and 2-arg `pymath_log`
overload pair would be reachable (this is the `bug-nilpy-stdlib-shim-table-
cannot-reach-an-overload` fix). Arity is not the blocker; the missing `Ln` is.

### `pow` and `atan2` are blocked on something else again — a 1-ulp libm gap

Measured on this box against CPython:

| | pxx | CPython |
| --- | --- | --- |
| `ArcTan(0.5)` | 0.46364760900080615 | **0.46364760900080609** |
| `2.0 ** 0.5` | 1.4142135623730949 | **1.4142135623730951** |
| `3.0 ** 2.5` | 15.588457268119901 | **15.588457268119896** |

So there is no correctly-rounded `pow` or `atan2` reachable to build these on:
NilPy's own float `**` is already 1 ulp off, which is
[[bug-nilpy-float-pow-loses-a-ulp-vs-libm]]. Implementing `math.pow` as
`Exp(y*Ln(x))` would be worse still — inexact in general, and wrong outright for
a negative base or `x = 0`. Shipping either would be a silent wrong value, so
neither was added.

**`math.pow` and `math.atan2` should be treated as blocked on
[[bug-nilpy-float-pow-loses-a-ulp-vs-libm]]**, not on this ticket's own work.
`crtl` has a correctly-rounded libm (`project_crtl_libm_correctly_rounded_dd`),
which is the likely source once someone wires it up.

### Remaining scope of this ticket
`math.log` (via route 1 or 2 above), plus `math.pow` / `math.atan2` once a
correctly-rounded libm is reachable. Section 3's name-hijack reasoning still
stands for all three.

### Gate for what landed
`make compiler/pascal26` (fixedpoint, 1 round) + `tools/gate.sh quick` GREEN +
`make test-nilpy`. Worth knowing for the next person: **`make compiler/pascal26`
does NOT compile pylib** — the `Ln` failure above only appears when a `.npy`
program is compiled, so a pylib edit must be checked by compiling a NilPy
program, not by building the compiler.
