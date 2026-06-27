# C: sqlite hits unsupported `AN_TERNARY` during IR lowering

- **Type:** bug (C frontend / IR lowering) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after `getpid` and ternary-middle
  comma parsing were fixed.
- **Closed:** 2026-06-27

## Symptom

sqlite stopped at:

```text
Unsupported linear node in IR codegen! Kind=10 node=2794 IRA=67 IRB=100111 IRC=100114 IRIVal=0
pascal26:56919: error: Unsupported linear node in IR codegen ()
```

`Kind=10` is `IR_UNSUPPORTED`; `IRA=67` is `AN_TERNARY`.

## Reduction

The failing source was in `balance_nonroot`:

```c
MemPage *pOld = (nNew>nOld ? apNew : apOld)[nOld-1];
```

`apNew` and `apOld` are local arrays of `MemPage *`. C decays the selected
ternary arm to a pointer value, then indexes that pointer.

## Cause

`IRLowerAddress(AN_INDEX)` handled simple pointer bases and nested pointer
indexing, but not computed pointer-value bases like `AN_TERNARY`. The generic
array/index path called `IRLowerAddress(base)`, which asked for the address of
the non-lvalue ternary expression and produced `IR_UNSUPPORTED`.

The parser also did not propagate pointer depth/base/pointee metadata through
pointer-valued ternary nodes, so even after address lowering was fixed, nested
indexing or field resolution could lose the selected pointer's element type.

## Fix

In C mode, `IRLowerAddress(AN_INDEX)` now recognizes computed pointer-value
bases and uses `IRLowerAST(base)` as the base pointer value, scaled by
`IRPointerStride(base)`.

`CNodePtrDepth`, `CNodePtrBaseTk`, and `CNodePointeeTk` now preserve pointer
metadata through `AN_TERNARY` nodes by selecting the pointer-decaying arm.

## Regression

Added `test/cternary_pointer_array_index_b103.c`, wired into `make test-core`.

## Result

sqlite advances to the next parser wall:

```c
char saveBuf[(sizeof(Parse)-((size_t)&(((Parse *)0)->sLastToken)))];
```

Filed [[bug-c-sqlite-offsetof-style-field-address-array-bound]].
