---
prio: 40
---

# operator `/` overload not declarable (use site already resolves it)

- **Type:** bug/gap (Pascal frontend, tiny) — Track P (shared parser.inc,
  A-gated)
- **Status:** backlog — filed 2026-07-11 while scoping
  [[feature-pascal-complex-numbers-ucomplex]]
- **Owner:** —

## Symptom

`ParseOperatorDef` (parser.inc ~1330) accepts only
`[tkPlus, tkMinus, tkStar, tkDiv, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe]` —
`operator / (a, b: complex): complex;` is rejected with "expected operator
symbol after operator keyword". The USE site (term parser ~6945) already
calls FindOpOverload for tkSlash operands, so the whole fix is adding
tkSlash to the declarable set (verify the term path then routes records to
the overload, mirroring tkStar).

Wanted by ucomplex (`z1 / z2`) and vecmath (`v / scalar`). While in there,
decide whether `tkMod` deserves the same one-liner (bignum may want it).

## Gate

`make test` + self-host fixedpoint byte-identical; extend
test_op_record_result.pas (or a sibling) with a `/` overload case.
