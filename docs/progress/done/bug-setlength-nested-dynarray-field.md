# SetLength on a nested sub-array slot through a record field

- **Type:** bug (compiler / codegen) — **Track A**
- **Status:** **DONE** — fixed (ir.inc), `make test` + cross-bootstrap green.
- **Opened / Closed:** 2026-06-22
- **Found by:** Track A, dynarray-aggregate FPC-vs-PXX robustness probe (not a
  Track B report — proactive).

## Symptom

```
SetLength expects an array variable in IR codegen
```
on `SetLength(rec.m[i], n)` where `m: array of array of Integer` is a record
field. A *local* nested `SetLength(m[i], n)` and a bare-field
`SetLength(rec.field, n)` both already worked.

## Cause

The `-102` (dyn-array SetLength) lowering had two special paths: (1) a depth>=2
**root array symbol** (covers local `m[i]`), and (2) a bare dyn-array **field**
`rec.field`. An `AN_INDEX` into a nested-array field (`rec.m[i]`) is rooted on the
record (dyn depth 0, so path 1 misses) and is not a bare field (path 2 misses),
so it fell through to the symbol-based generic path, whose `IR_LEA`-of-a-symbol
assumption fails → the error.

## Fix

Add a third branch: a non-array-symbol-rooted `AN_INDEX` target with
`NodeDynDepth >= 1` routes to `IR_SETLEN_DYN` via the slot-address path, with leaf
element metadata from the dyn-array base (`NodeDynBaseTk`/`NodeDynBaseRec` already
walk the field+index chain). The array-symbol-rooted nested case keeps the
depth>=2 branch (no regression).

## Verification

- `test/test_nested_dynarray_field.pas` (record `array of array of Integer`,
  SetLength sub-arrays, read back) → `sum=99`, matches FPC.
- Local nested `m[i]` unchanged. `make test` + fpc-check byte-identical,
  cross-bootstrap (i386/aarch64/arm32) byte-identical.

## Log
- 2026-06-22 — Found + fixed (Track A). Part of a dynarray-in-aggregate
  robustness pass (siblings: bug-dynarray-in-record-corrupt,
  bug-named-dynarray-field-setlength). Not separately re-pinned; rides the next
  `make pin`.
