---
prio: 40
---

# Multi-dim ORDINAL global array initializer skipped (`int a[2][3] = {{1,2,3},{4,5,6}}` stays zero)

- **Type:** bug (cfront global init). Track C.
- **Found:** 2026-07-08 while landing bug-c-init-brace-elision-nested
  (test/cinit_elision_nested_b193.c originally probed it; check removed).
  Pre-existing — pinned stable fails identically, NOT a walker regression.

## Symptom
File-scope multi-dimensional ordinal arrays with a brace initializer read 0:
`int arr2[2][3] = {{1,2,3},{4,5,6}}; arr2[1][2]` → 0. Two causes in
ParseCGlobalVarDecl:
1. The dims loop only captures dim 1 (`arrLen`); dims 2+ are token-skipped, so
   `AllocArray` reserves `dim0` elements, not the product, and `SymArrNDims`
   is never set (body indexing `arr2[i][j]` then relies on... whatever the
   1-D fallback does — also verify reads).
2. The nested-brace init fails `CBraceIsFlatIntInit` → whole initializer
   balanced-skipped, no PendingInits recorded.

## Fix sketch
Capture all dims (mirror the LOCAL decl path, which handles `dimSpan[]` /
`SymArrNDims`), then route the initializer through the recursive brace-elision
walker (`CInitWalkArray`, landed with bug-c-init-brace-elision-nested) with
the sym's dim metadata — the walker already handles nested/elided dims via
`CInitDimSpanAt`; only this ordinal-global entry point is missing.

## Gate
`int a[2][3]` global (nested + flat elided inits) reads correct values on
x86-64; `make test` + self-host; check corpus for users.
