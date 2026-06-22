# Bignum library — arbitrary-precision integers (deterministic test app)

- **Type:** feature
- **Status:** done
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
- 2026-06-22 — **DONE** (track B): remaining surface landed —
  `BigDivMod` (long division, trunc-toward-zero, binary-search per limb),
  `BigCompare` (signed), `BigIsZero`, `BigNegate`, `BigAddSigned`/`BigSubSigned`,
  `BigFromStr`, and `BigModPow` (square-and-multiply). New oracle
  `examples/bignum/bigmath.pas` checks DivMod invariant `q*b+r=a`, FPC
  trunc-toward-zero signs, signed add/sub, ModPow known vectors (4^13 mod 497,
  2^10 mod 1000, 3^5 mod 7) and a modpow-square self-consistency check; wired into
  `make lib-test` + `make demos`. Fixed an infinite loop in `BigModPow`: the
  `e := e div 2` step called `BigDivMod(e,two,q,e)` — quotient/remainder args
  swapped, so `e` got the remainder and stayed odd forever. (That hang, killed
  with exit 144, is what cut the previous track-B session mid-run.)
  Commit 6ff75e0.
