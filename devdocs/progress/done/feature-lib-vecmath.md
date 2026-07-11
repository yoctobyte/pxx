---
prio: 42
---

# vecmath library: TVec2/3/4 + TMat with operator overloads — Track B

- **Type:** feature (library) — Track B
- **Status:** done
  bignum — nice library legwork that is testable, and we all love more
  tests"), sibling of [[feature-pascal-complex-numbers-ucomplex]]
- **Owner:** fable-p

## What

`lib/rtl/vecmath.pas`: TVec2/TVec3/TVec4 (Double fields), TMat3/TMat4.
Operators: `+ - *` (vec op vec componentwise, vec op scalar, mat*mat,
mat*vec), `=`; functions Dot, Cross (3D), NormSq, Norm, Normalize, Lerp,
mat identity/translate/scale/rotate, Transpose, Determinant (3x3/4x4).
`v / scalar` waits on [[feature-pascal-operator-slash-overload]] (VScale
meanwhile). Overload dispatch keys on the LEFT operand → scalar*vec not
registrable; provide function form and document.

## Why

Real demo fuel (the E-track games/GUI apps want this) AND a deliberate
operator-overloading workout — the feature has 2 thin tests today; matrices
give it record-result chains (`(a*b)*v + w`), const params, nested record
fields. Every identity is exactly testable.

## Tests

lib-suite golden test: algebraic identities with exact expected output —
cross(x̂,ŷ)=ẑ, dot orthogonality, |normalize(v)|=1, M·M⁻¹ spot checks
(integer-friendly cases to dodge FP noise), mat*vec against hand-computed
vectors, operator chains. Integer-valued inputs keep expected strings exact
(FP-determinism rules).

## Gate

Track B: build with `$(PXX_STABLE)`, `make lib-test` green. Frontend gaps →
P-lane ticket, don't patch here.

## Log
- 2026-07-11 — resolved, commit 32758fcc.
