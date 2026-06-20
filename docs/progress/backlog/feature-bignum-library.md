# Bignum library — arbitrary-precision integers (deterministic test app)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** demo-eligible-as-library from idea-demo-app-candidates. Sibling
  to feature-json-library et al. Own unit, FPC-ish naming (FPC has no standard
  bigint — only GMP bindings — so this is genuinely ours), no port.

## Goal

A `BigInt` unit: signed arbitrary-precision integers stored as an array of
machine-word limbs. Schoolbook algorithms first (correctness over speed);
Karatsuba etc. optional later.

## Surface (sketch)

- type `TBigInt` (limb dynarray + sign)
- `Add` / `Sub` / `Mul` / `DivMod` / `Compare` / `Negate`
- `FromString` / `ToString` (base 10), `FromInt64`
- `Pow`, `Factorial`, `ModPow` (modular exponentiation)

## Coverage

dynamic arrays (limbs) · carry/borrow Int64 + UInt64 math (stresses 64-bit on
32-bit targets) · managed-string decimal format/parse · operator-ish routines.
Integer-deterministic by construction.

## Acceptance / oracle

- `Factorial(1000)` exact decimal string (known constant) — byte-identical
  across all targets.
- `ModPow` against known vectors; `DivMod` invariants (`q*b + r = a`).
- Demo: `examples/bignum/` prints `Factorial(1000)`, a couple of `Pow`/`ModPow`
  results, vs embedded expected values.

## Notes

- Foundation for any future big-integer crypto (RSA toy etc.) — that stays a
  separate ticket; this is just the arithmetic core.

## Constraints

Own `.pas` unit; FPC-ish naming; no port; no self-host / cross regression.

## Log
- 2026-06-19 — Opened from the demo/library organization pass.
- 2026-06-20 — **BigMul + BigSub landed** (track B): `lib/rtl/bignum.pas` now has
  full bignum×bignum multiplication (schoolbook O(n²)) and unsigned subtraction.
  The record-fn codegen crash (bug-record-fn-codegen-crash) that blocked these is
  fixed in pinned v11+. `BigMulSmall` remains for the small-multiply fast path.
  Remaining: `BigDivMod`, `BigCompare` (signed), `BigNegate`, `ModPow`.
