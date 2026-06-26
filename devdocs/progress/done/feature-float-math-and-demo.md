# Float math library (Single+Double) + numerical float demo

- **Type:** feature — **Track B**
- **Status:** done — green on pinned v35 (commit a25136d)
- **Opened:** 2026-06-22
- **Owner:** —

## Goal

A comprehensive floating-point math library (the foundation a float demo needs),
plus a float demo/oracle. Pure-Pascal fallback, native x86-64, **no asm yet**
(other-CPU goniometric asm comes later). **Single + Double** overloads only — no
Extended (it is aliased to Double; see feature-extended-type-support).

## Delivered

- `lib/rtl/math.pas` expanded: Tan, ArcSin/ArcCos/ArcTan2, Sinh/Cosh/Tanh +
  inverses, Cot/Sec/Csc, Log10/Log2/LogN, Hypot, IntPower, Floor/Ceil/FMod, Sign,
  float Min/Max, DegToRad/RadToDeg — on top of the existing Pi/Sqrt/Exp/Ln/Sin/
  Cos/ArcTan/Power core. Single overloads (widen→Double→narrow) for the
  transcendental/utility set. Reuses builtins Trunc/Round/Frac/Int.
- `examples/mathf/mathdemo.pas` — tolerance oracle + numerical showcase: every
  function vs textbook constants (1e-9); Single overloads (1e-5); Single→Double
  conversion; mixed single/double promotion (resolves Double); the `real` type;
  Machin π / e-series / Simpson ∫sin / Newton √2. Ends `ALL OK`; wired into
  `make lib-test` + `make demos`.

## Foundations verified (compiler, on v34/v35)

- `Single→Double` conversion and narrowing assignment: OK.
- Overload resolution Single vs Double: OK.
- Mixed-type promotion `single*double → double`: OK.
- `real` behaves as Double on x86-64. Cross-target consistency: separate ticket
  feature-real-cross-target-consistency (Track A, qemu runs).

## Gaps found (filed)

- bug-untyped-float-const: `const X = 1.5;` rejected (typed const works); also
  `Single(expr)` value cast not parsed. Worked around with clean idiomatic Pascal.

## Determinism

Floats are not guaranteed byte-identical across targets, so the oracle uses
tolerance compares + `ALL OK`, never raw float output.

## Log
- 2026-06-22 — Implemented + green on pinned v35 (a25136d). Math library is the
  foundation; float demo built on it. Done.
