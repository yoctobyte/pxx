# C: `f()->field` — field/index of a pointer-returning call result

- **Type:** bug
- **Track:** C (C frontend) / IR
- **Opened:** 2026-06-26
- **Found-by:** lua bisection — lobject.c `localeconv()->decimal_point[0]`
  (liolib/lobject/lparser all hit `IRLowerAddress(AN_CALL)` = IRA=8).

## Symptom

```c
struct L { int v; int w; };
struct L *g(void);
... g()->w ...        /* gcc: gg.w ; pxx: IR_UNSUPPORTED (AN_CALL in IRLowerAddress) */
```

`CNodeIsPointer` does not recognise an `AN_CALL` whose return type is `tyPointer`,
so ParseCPostfix never inserts the `AN_DEREF` for `->`, and the field's base
becomes the bare call → `IRLowerAddress(AN_CALL)` → Unsupported.

## Attempted fix + why reverted (IMPORTANT)

Adding `AN_CALL` (pointer-returning) to `CNodeIsPointer` + `CNodePtrElemRec`
(`ProcRetPtrElemRec[procIdx]`) made it COMPILE, and `g()->v` (offset 0) is
correct — but `g()->w` (offset 4) returns 0 and `g()->dp[0]` is garbage. The
FIELD-VALUE lowering path (`IRLowerAST(AN_FIELD)` for `return g()->w`) does not
resolve the record of an `AN_DEREF`-over-`AN_CALL` base, so the field offset comes
out 0 (offset-0 fields work by coincidence). That is a SILENT miscompile — worse
than the loud Unsupported — so the change was reverted (commit not landed).
`ProcRetPtrElemRec[g]` itself IS populated (ParseCDeclType sets CTypeElemRec for
`struct L *`, captured before params), and `ResolveNodeRec(AN_DEREF)` already has
an AN_CALL-base path (symtab.inc ~4828); the gap is the value-read field path not
using it.

## Correct fix

1. `CNodeIsPointer`/`CNodePtrElemRec`: recognise pointer-returning `AN_CALL`.
2. Ensure the field-VALUE lowering (`IRLowerAST(AN_FIELD)`, and the index path
   for `f()->arr[i]`) resolves the record of an `AN_DEREF(AN_CALL)` base (via
   `ResolveNodeRec`, which already handles it) and applies the field offset —
   currently only the offset-0 case is right.
3. Verify `g()->w` (non-zero offset), `g()->ptr[i]`, and `g().field`
   (struct-by-value return) all match gcc before landing. Pervasive in lua
   (`localeconv()->decimal_point[0]`, accessor macros over call results).

## Resolution
- 2026-06-26 — FIXED. CNodeIsPointer/CNodePtrElemRec recognise a pointer-returning
  AN_CALL; ResolveNodeRec already resolved the AN_DEREF(AN_CALL) record. The
  earlier "offset 0" was a RED HERRING from a separate bug: struct-typed GLOBALS
  did not record their record id (ParseCGlobalVarDecl skipped LastTypeRecId), so
  `gg.f` always landed at offset 0 — fixed too. g()->field / g()->n->x verified vs
  gcc. Fixture ccall_field_b31.c (=42). (g()->arr[i] and global initializers/
  arrays remain a separate gap — globals are not materialised as real arrays.)
