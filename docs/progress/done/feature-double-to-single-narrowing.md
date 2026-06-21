# Double literal / value → Single narrowing on assign and argument

- **Type:** feature (float type coercion)
- **Status:** DONE (2026-06-21) — subsumed by feature-single-first-class
- **Owner:** —
- **Opened:** 2026-06-20
- **Closed:** 2026-06-21

## Resolution (2026-06-21)

Done as part of feature-single-first-class (see that ticket). The internal-call
Single ABI was the real blocker, exactly as the 2026-06-20 investigation note
predicted. Once the ABI narrows/widens at the tySingle boundary on every target,
the `TypesCompatible` clause (a float formal accepts any float or ordinal actual,
compatible-match only) was safe to add — `ScaleS(1.5, 3)` now prints 4.5000, not
0.00. Assign-narrowing already worked (EmitStoreVar cvtsd2ss). Covered by
test/test_single_first_class.pas and the re-enabled Single case in
test/test_cross_float_return.pas. All 4 Linux targets correct + byte-identical.

## Problem

A `Double`-typed value (notably a float literal, which is `tyDouble`) does not
narrow to a `Single` target. Passing a float literal to a `Single` parameter
fails overload resolution outright:

```pascal
function ScaleS(s: Single; k: Integer): Single;
begin ScaleS := s * k; end;
...
ScaleS(1.5, 3);   { error: no overload of ScaleS matches these arguments }
```

`MatchProcCall` sees `arg[0] = 19 (tyDouble)` vs `param[0] = 18 (tySingle)` and
rejects it. The same narrowing is presumably missing on plain assignment
(`var s: Single; s := 1.5;`) and on `Single` function results fed a Double.

Found while writing test/test_cross_float_return.pas (the Single case had to be
dropped; the test now covers Double only).

## Why it matters

`Single` is a legitimate type; FPC accepts a real literal into a Single and a
Single param fed a Double constant (with the usual precision warning). PXX should
narrow with `cvtsd2ss` (x86-64) / `fcvt s,d` (aarch64) / `vcvt.f32.f64` (arm32)
at the coercion point, mirroring the int→float widening that
feature-int-to-float-assign added.

## Scope / where to fix

1. **Overload matching** (`MatchProcCall`): accept `tyDouble` (and int) actuals
   for a `tySingle` formal — a widening/narrowing-compatible float match, ranked
   below an exact match so a true Single arg still wins.
2. **Coercion at the narrowing point**, wherever a Double value flows into a
   Single slot: assignment (IR_STORE_SYM / IR_STORE_MEM — pairs with the int→float
   branch already there), argument passing, and Single function return. Emit the
   double→single convert; the value model then carries the narrowed value.
3. Mind the float-literal path: a literal assigned/passed to a Single may be
   constant-foldable to single bits at compile time instead of a runtime convert.

## Acceptance

`s := 1.5`, `ScaleS(1.5, 3)`, and a `Single` function result fed a Double all
produce the correct single-precision value; FPC-comparable; `make test` +
`make cross-bootstrap` green. Add the Single case back to
test/test_cross_float_return.pas (or a dedicated test).

## Log
- 2026-06-20 — Opened from the cross-float-returns arc; the Single param/literal
  case is orthogonal to function-return enablement so split out here. Related:
  feature-int-to-float-assign (the widening counterpart, done x86-64),
  feature-cross-float-returns.

## Investigation 2026-06-20 (Track A) — blocked on Single internal-call ABI

Overload matching is NOT the only gap. Even passing a `Single` VARIABLE to a
`Single` parameter on an INTERNAL (PXX-ABI) call returns 0.00 — the internal
call's float-arg marshalling does not handle `tySingle` params (it carries
floats as double bits and never narrows/widens at the param boundary; only the
EXTERNAL C-call path does cvtsd2ss for Single params, ir_codegen.inc ~2732).
Double->Single ASSIGN already works (EmitStoreVar narrows). So the real fix is
the internal-call Single ABI (caller arg width + callee prologue + Single param
load + Single result), i.e. the feature-single-first-class arc — NOT just the
MatchProcCall clause. Tried adding the float widen/narrow clause to
TypesCompatible: `ScaleS(1.5,3)` then compiles but prints 0.00 (silently wrong),
which is worse than the clean overload error, so reverted. Keep this ticket
under the Single-first-class arc; do the ABI first, then the overload clause.
