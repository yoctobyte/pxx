---
track: B
prio: 55
type: bug
blocked-by: []
summary: "Tanh(x) is (e^x - e^-x)/(e^x + e^-x), so for |x| >= ~710 it computes Inf/Inf = NaN where the answer is exactly +-1. Tanh(Inf) is NaN too. glibc and CPython both give 1.0. Present in BOTH float modes — a wrong value, not a rounding question. Also check the small-|x| end: the same formula subtracts two nearly-equal numbers."
status: done
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

---

## RESOLVED 2026-08-15 — and it was all six, not just Tanh

The ticket said to check the small-|x| end and grep the siblings before closing.
Both paid off: measuring the family against glibc over 2,044 arguments found
that **every one of the six was wrong somewhere**, and for one shared reason.

| function | defect | measured |
| --- | --- | --- |
| `ArcSinh` | small-x cancellation | `ArcSinh(1e-15)` = 1.1102e-15 vs 1e-15 — **11% wrong** |
| `ArcTanh` | same | `ArcTanh(1e-15)` — **11% wrong** |
| `Sinh` | same | `Sinh(1e-15)` = 1.0547e-15 — **5% wrong** |
| `ArcSinh` | negative-x cancellation | **1497 ulp** at x = -94 |
| `ArcSinh`/`ArcCosh` | `x*x` overflows past 1.3e154 | `ArcSinh(1e200)` = Inf, true answer 461.2 |
| `ArcCosh` | domain error answered as a VALUE | `ArcCosh(0.5)` = 0.0, indistinguishable from `ArcCosh(1.0)` |
| `Sinh`/`Cosh` | premature overflow | `Sinh(710)` = Inf; 1.117e308 is an ordinary double |
| `Tanh` | Inf/Inf | NaN for \|x\| >= 710 and at +-Inf |

**One cause:** every formula routed a small answer through a quantity near 1,
where the bits that ARE the answer fall off the bottom of the significand. So
the fix went underneath rather than into six formulas — `ExpM1` and `LnP1` were
added (Kahan's and Goldberg's constructions, which divide out the rounding of
`Exp`/`Ln` using an accurate `Ln`; both cheap now that the fast log/exp landed),
and the six became the standard stable identities.

Neither primitive is exported: `expm1`/`log1p` are libc names and every
interface name here is in scope for C through pxxcio, so a Pascal `Expm1` would
hijack libc's exactly like the documented `Pow`/`Log`/`CopySign` trap. FPC's
public spelling `LnXP1` does not collide — adding it is a separate FPC-compat
item, filed as [[feature-b-rtl-lnxp1-fpc-compat]].

Two things measurement corrected mid-fix, neither of which was reasoning I would
have trusted otherwise:

- `Exp(ax - ln2)` for large `Sinh`/`Cosh` was **307 ulp** out: at x = 710,
  `ulp(x)` is 1.1e-13, so subtracting ln2 damages the ARGUMENT and `exp`
  turns that into hundreds of ulp of result. `(0.5*w)*w` with `w = Exp(0.5*ax)`
  costs two roundings instead — halving is exact.
- The `expm1(-2x)` form of `Tanh` was 3 ulp near saturation;
  `1 - 2/(Exp(2x)+1)` for |x| >= 1 is **bit-exact with glibc** over the whole
  range.

Result over 2,044 arguments: worst 1 ulp everywhere except `ArcTanh` at 2, and
`Tanh` bit-exact. **Zero Inf/NaN mismatches.**

`test/lib_math_fast_tolerance.pas` grew to 102 checks pinning every row above.
Gate: `tools/gate.sh lib` GREEN, which includes `cmath_hyperbolic_family_b383.c`
— so the C side is unaffected and nothing hijacked libc. Cross-verified under
qemu on i386, aarch64 and arm32.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
