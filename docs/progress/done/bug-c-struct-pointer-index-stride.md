# C: `p[i]` / `p+i` on a struct pointer uses the wrong element stride

- **Type:** bug (HIGH impact — silent miscompile)
- **Track:** C (C frontend) / IR
- **Opened:** 2026-06-26
- **Found-by:** lua import via full-file bisection (lapi.c `index2value`, the
  `s2v(stack + idx)` stack-element pattern).

## Symptom (minimal, no lua headers)

```c
struct V { int val; };
int main(void){
  struct V a[3];
  a[2].val = 42;
  struct V *p = a;
  return p[2].val;          /* gcc 42, pxx 0 */
}
```

`a[2].val` direct = 42 (correct). `p[0].val` = 42 (correct). But `p[2].val`
reads 0. `(char*)&a[2] - (char*)&p[2]` = 8 (should be 0): `p[2]` is addressed
with **stride 8 (pointer size) instead of `sizeof(struct V)` = 4**. So indexing a
struct pointer beyond element 0 lands on the wrong object — a SILENT miscompile
(no error), already present in the committed compiler. Pervasive in lua/sqlite
(every `stack[i].field` / `p[i].field`).

## Where to look

`ir.inc` ~604–619 (pointer indexing `p[i]`): it already intends
`if PtrElemTk = tyRecord then elemSize := RecSize(PtrElemRec) else
TypeSize(PtrElemTk)`. The observed stride 8 means the `tyRecord` branch is NOT
taken for `struct V *p` — i.e. the symbol's `PtrElemTk`/`PtrElemRec` is not
tyRecord/the struct (so it falls to `TypeSize` = pointer size 8), OR the
`p = a` array-decay assignment clobbers p's element metadata. First check
`Syms[p].PtrElemTk`/`PtrElemRec` right after `struct V *p` is declared and again
after `p = a`. (RecSize(V) is correct — `sizeof(struct V)` returns 4.) Fix so the
struct element size is used; then `p[i].field`, `(p+i)->field`, and the
`bug-c-field-on-pointer-arithmetic` Unsupported all resolve.

## Note

This is the ROOT of `bug-c-field-on-pointer-arithmetic`: once pointer arithmetic
on a struct pointer scales correctly AND `(p+i)` keeps its pointer type, both
`p[i].field` and `(p+i)->field` work. A type-only fix for `(p+i)->field` (tagging
the binop pointer) was tried and reverted because it turned the loud
"Unsupported" into a SILENT wrong value via this stride bug — fix the stride
first.

## Resolution
- 2026-06-26 — FIXED for local arrays. Root cause was NOT the pointer-index path
  (that already used RecSize) but the C array DECLARATION: `struct V a[N]` called
  AllocArray without setting the global LastTypeRecId, so AllocArray sized record
  slots by a default instead of RecSize -> `a[i]` used the wrong stride, and
  `a[i]` vs `p[i]` disagreed. Now the C local-array decl sets
  `LastTypeRecId := CTypeBaseRec` for tyRecord elements before AllocArray.
  Self-host byte-identical; fixture test/cstruct_array_stride_b23.c (=42).
  FOLLOW-UP: global arrays of structs (ParseCGlobalVarDecl) and struct FIELDS
  that are arrays-of-struct may share the same missing-LastTypeRecId pattern —
  verify/extend. `bug-c-field-on-pointer-arithmetic` ((p+i)->field Unsupported)
  is now the only remaining piece for that construct.
