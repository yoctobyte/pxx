# Transcendental math library (Sqrt/Sin/Cos/Ln/Exp/ArcTan/Power/Pi/Abs)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-18 (companion to feature-float-str-val, #5 of the language arc)
- **Resolved:** 2026-06-18 (commit 5e8436e) — added to lib/rtl/math.pas,
  byte-identical to FPC at 8 decimals, cross-bootstrap clean.

## Scope

Pure-Pascal floating-point transcendentals in `lib/rtl/math.pas` (no libm — keeps
the no-libc design): `Pi`, `Abs(Double)`, `Sqrt` (Newton), `Exp`/`Ln` (range
reduction + Taylor/atanh series), `Sin`/`Cos` (mod-2π reduction + Taylor),
`ArcTan` (half-angle reduction + Taylor), `Power(Double,Double)` (= exp(e·ln b)).
The existing integer `Min`/`Max`/`Power`/`Gcd`/`Lcm` are unchanged; float `Power`
is an overload, float `Abs` is new.

## Bugs found + handled along the way

- **Long float literals** (>~16 significant digits) mis-parsed — `coeff`
  saturated at 18 digits but kept counting dropped fractional digits, scaling the
  value off by powers of ten (`3.14159…846` → 0.0314). **Fixed** in
  `StrToDoubleBits` (lexer.inc): only count absorbed fractional digits; dropped
  integer-part digits bump the exponent. Cross-bootstrap byte-identical.
- **`Result` (float) read-modified in a loop → 0** — pre-existing codegen bug,
  filed as feature-result-in-loop. Worked around: accumulate in a local, assign
  Result once.
- **int→float assignment** missing conversion (feature-int-to-float-assign) —
  the whole lib uses float literals (`2.0`, not `2`) to avoid it.

## Acceptance

test/test_math.pas exercises all functions; output byte-identical to FPC
(`uses math`) at 8 decimals incl. the identity sin²+cos²=1. make test green.

## Log
- 2026-06-18 — implemented; resolved.
