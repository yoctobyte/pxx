---
prio: 44
---

# unit-scoped operator definitions silently skipped → record binop miscompile

- **Type:** bug (compiler core / shared parser.inc + ir.inc) — Track A
- **Status:** filed 2026-07-11 while landing
  [[feature-pascal-operator-decl-fpc-compat]] (found the moment a unit-scoped
  operator was tried; pre-existing — pinned stable segfaults too).
  Self-resolved same session under combined P+A assignment.
- **Owner:** fable-p

## Symptom

Any `operator` definition in a unit's implementation section was silently
skipped: the impl decl loop in `ParseUnit` (parser.inc ~17406) had no
`operator` dispatch, so the whole definition fell through `else Next`
token-by-token. No overload was registered; `a + b` on records then fell
through to the scalar `IR_BINOP`, adding the records' first qwords and using
the sum as a copy source → SIGSEGV at run time (rep movsb with the record
VALUE in rsi). Program-scoped operators were fine (top-level decl loop has the
dispatch).

## Fix

1. `ParseUnit` impl loop: dispatch `'operator'` → `PreScanPass := False;
   ParseOperatorDef; PreScanPass := True` (same emit-in-place pattern as the
   top-level loop and `initialization`).
2. `ir.inc` binop lowering: arithmetic op (`+ - * / div mod`) on a record
   operand with no registered overload is now a compile error instead of a
   silent scalar-binop miscompile. Comparisons left alone (method-pointer
   `=`/`<>` are legitimate record compares).

Note: an interface-section `operator` heading is still skipped silently (the
overload table is global, so the implementation's registration is visible
everywhere; FPC-style interface-gated visibility is not modeled). An
interface-only decl with no implementation now errors at the use site via (2).

Known limitation: the operator body is emitted during the unit's prescan, so
it can only call impl routines declared ABOVE it (same as `initialization`
ordering rules — fine in practice, operators sit near the top).

## Gate

`make test` + self-host fixedpoint byte-identical. Tests:
`test/test_op_fpc_named_result.pas` (program) + unit-scoped operator test.
