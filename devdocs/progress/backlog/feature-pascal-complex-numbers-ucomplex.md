---
prio: 45
---

# ucomplex library (complex numbers, FPC-compatible API) — Track B

- **Type:** feature (library) — **Track B**. Operator overloading already
  EXISTS in pxx (`operator + (a, b: T): T;` desugared to `__op__NN`,
  parser.inc ParseOperatorDef; exercised by test_op_overload /
  test_op_record_result) — so this is library legwork, not a frontend
  feature. (Ticket originally misfiled as Track P on the wrong assumption
  the feature was missing; corrected 2026-07-11 after verifying a complex
  `*`/`+` overload chain compiles and runs on pxx today.)
- **Status:** backlog — user-requested 2026-07-11
- **Depends on:** [[feature-pascal-operator-decl-fpc-compat]] for natural
  `z1 / z2` syntax (declarable op set today lacks `/`) — can land with a
  `cdiv` function first and switch when that P one-liner lands.
- **Owner:** —

## What

Port FPC rtl-extra `ucomplex` to `lib/rtl/ucomplex.pas`, API-compatible
where pxx allows:

```pascal
type complex = record re, im: Double; end;
const i: complex = (re: 0.0; im: 1.0);
operator + - * (complex, complex) and (complex, Double) forms;
operator = ;
function cinit(re, im: Double): complex;
{ cmod, carg, conjugate, csqrt, cexp, cln, csin, ccos, ctan }
```

Known pxx-vs-FPC deltas to document in the unit header:
- no `operator :=` (implicit Double→complex): use `cinit`; mixed
  arithmetic needs the complex on the LEFT (overload dispatch keys on the
  left operand's record type — `operator + (r: Double; z: complex)` is not
  registrable).
- `/` via `cdiv(a, b)` until the slash ticket lands.

## Why (user)

Complex numbers = the one Extended-Pascal idea worth having; and this is a
deliberate WORKOUT for the operator-overloading feature — early feature,
nearly untested (2 thin tests: `+` on records, `<`/`>` comparisons; `*`,
mixed complex/Double operands, operator chains, const-param operators all
uncovered). Same rationale as the vector/bignum tickets:
[[feature-lib-vecmath]], [[feature-lib-bignum-operators]].

## Tests (the point)

Golden test in the lib suite: arithmetic identities ((3+4i)(1−2i)+(3+4i) =
14+2i), csqrt(−1) = i, cmod(3+4i) = 5, cexp(i·π) ≈ −1, conjugate/carg;
exact expected strings (FP-determinism rules — own-RTL math, watch libm
divergence). Plus operator-chaining and complex-op-Double cases, which
double as frontend regression coverage.

## Gate

Track B: build with `$(PXX_STABLE)`, `make lib-test` green. Frontend gaps
found while porting → ticket the P lane, don't patch here.
