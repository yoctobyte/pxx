---
prio: 75  # silently wrong data, no crash — the worst failure mode
---

# Whole-array assignment of an N-D array copies garbage (no error, no crash)

- **Type:** bug (codegen / assignment lowering) — **Track A**
- **Status:** done
- **Opened:** 2026-07-12, found while fixing [[bug-array-assign-to-var-param]]
  (the N-D case of that ticket's regression test failed for a *different*
  reason).

## Symptom

`b := a` between two multi-dimensional arrays copies one element's width and
leaves the rest as whatever was on the frame. No error, no crash — just wrong
data:

```pascal
program nd;
type TM = array[0..1, 0..2] of Integer;
var a, b: TM; i, j: Integer;
begin
  for i := 0 to 1 do for j := 0 to 2 do a[i][j] := i * 3 + j;
  b := a;
  for i := 0 to 1 do for j := 0 to 2 do Write(b[i][j], ' ');
  WriteLn;   { got: "4235801 0 0 0 0 0"   want: "0 1 2 3 4 5" }
end.
```

Local-to-local, no parameters involved. 1-D arrays are fine (they take the
IR_COPY_REC path).

## Cause

The whole-static-array assign path in `IRLowerAST` (`compiler/ir.inc`, the
`AN_ASSIGN` static-array branch) was guarded by `SymArrNDims[...] <= 1`, so any
N-D array fell through to the ordinary scalar store path — which moves a single
element's width. N-D arrays are in fact stored FLAT, and `ArrLen` is already the
flattened element count, so a single `IR_COPY_REC` of `ArrLen * elemSize` copies
the whole thing correctly. The guard was simply too conservative.

## Why it matters

Worse failure mode than its sibling ticket: that one segfaults (loud), this one
returns quietly wrong numbers. Any code doing matrix/grid copies by assignment
gets silent corruption.

## Fix

Drop the `<= 1` guard so N-D arrays take the same flat IR_COPY_REC path as 1-D.

## Acceptance

- The case above prints `0 1 2 3 4 5`.
- Covered in `test/test_array_var_param_assign.pas` (the `TM` / `BumpM` case,
  which exercises N-D both local-to-local and through a `var` param).
- `make test` green; self-host byte-identical.

## Log
- 2026-07-12 — resolved, commit 1d53fd32.
