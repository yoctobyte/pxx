---
track: B
prio: 55
type: bug
blocked-by: []
summary: "Tanh(x) is (e^x - e^-x)/(e^x + e^-x), so for |x| >= ~710 it computes Inf/Inf = NaN where the answer is exactly +-1. Tanh(Inf) is NaN too. glibc and CPython both give 1.0. Present in BOTH float modes — a wrong value, not a rounding question. Also check the small-|x| end: the same formula subtracts two nearly-equal numbers."
---

# `Tanh` returns NaN for |x| >= 710, and for Inf

- **Type:** bug — **Track B** (`lib/rtl/math.pas`).
- Found 2026-08-15 while edge-testing the fast log/exp path. **Pre-existing** —
  it fails identically under `-dPXX_FLOAT_EXACT`, so it is not from that work.

## Symptom

```
Tanh(+Inf) = Nan        glibc/CPython: 1.0
Tanh(-Inf) = Nan        glibc/CPython: -1.0
Tanh(800)  = Nan        glibc/CPython: 1.0
Tanh(20)   = 1.0        (correct)
```

## Cause, which is right there in the source

```pascal
function Tanh(x: Double): Double;
var ex, enx: Double;
begin
  ex := Exp(x);
  enx := Exp(-x);
  Result := (ex - enx) / (ex + enx);
end;
```

At x = 800, `Exp(800)` overflows to `+Inf` and `Exp(-800)` underflows to `0`, so
the expression is `(Inf - 0) / (Inf + 0)` = `Inf / Inf` = **NaN**. The true value
saturated to exactly 1.0 more than 600 orders of magnitude earlier.

This is a **wrong value**, not an accuracy divergence — `devdocs/dev/float-policy.md`
lists "NaN where a number belongs" as a bug in both modes, always.

## Check the OTHER end while in here

The same formula subtracts two nearly-equal numbers when x is small: for
x = 1e-10, `ex` and `enx` are both ~1, and `ex - enx` cancels away most of the
significand. Measure `Tanh` against glibc for small |x| before choosing the fix
— if it is bad there too, both ends have one cause (the formula) and one fix,
which is the outcome to prefer over patching the Inf case alone.

## Fix direction

The standard formulation, which fixes both ends at once:

- |x| >= ~20: return `+-1.0` directly (the double result is already saturated).
- otherwise use `expm1`: `tanh(x) = expm1(2x) / (expm1(2x) + 2)`, which keeps
  the small-|x| relative accuracy the subtraction destroys.

Note `expm1` does not exist in `lib/rtl/math.pas` yet. If adding it is out of
scope, `t := Exp(2*x); (t - 1) / (t + 1)` at least removes the Inf/Inf and costs
one Exp instead of two — but it does NOT fix the small-|x| cancellation, so
prefer the expm1 route and say so if you take the cheap one.

## Grep the siblings before closing

Per `devdocs/dev/normalise-dont-special-case.md`: `Sinh`, `Cosh`, `ArcSinh`,
`ArcCosh`, `ArcTanh` are built from the same `Exp`/`Ln` pieces. `Sinh(Inf)` and
`Cosh(Inf)` were spot-checked and correctly give `Inf`, but the rest were not.

## Gate

`tools/gate.sh lib` plus rows in `test/lib_math_fast_tolerance.pas` covering
`Tanh` at `+-Inf`, at 800, at 20, and at 1e-10 — the last one is the row that
proves the small-|x| half was fixed rather than the large-|x| half alone.
