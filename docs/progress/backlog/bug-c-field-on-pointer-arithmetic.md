# C: `(p + i)->field` (field on a computed pointer) fails / Unsupported

- **Type:** bug
- **Track:** C (C frontend)
- **Opened:** 2026-06-26
- **Found-by:** lua import via the full-file-bisection method — lapi.c's
  `index2value` uses `s2v(L->top.p + idx)`, and `s2v(o)` = `(&(o)->val)`, i.e.
  `&(ptr + idx)->val`.

## Symptom (minimal, no lua headers)

```c
struct V { int val; };
struct V *base(void);
int *f(int idx){ struct V *p = base(); return &(p + idx)->val; }
```

gcc: fine. pxx: `Unsupported linear node in IR codegen`. `s2v(p)` (no `+ idx`)
works; `p + idx` alone works; only `(p + idx)->field` fails.

## Root cause

Pointer arithmetic `p + i` builds an `AN_BINOP` whose result type is computed by
`CBinResultTk` as Integer/Int64 — it does NOT preserve the pointer type. So for
`(p + i)->field`, `CNodeIsPointer((p+i))` is false, ParseCPostfix does NOT insert
the `AN_DEREF`, and the field's base becomes the bare `AN_BINOP`. `IRLowerAddress`
has no `AN_BINOP` case, so it falls through to `IR_UNSUPPORTED`. (The pointer
VALUE is fine — the IR already scales `p + i` by the element size; only the
node's TYPE is wrong.)

## Fix sketch (multi-part — pointer type propagation)

1. `CMakeBinop`: when the op is `+`/`-` and one operand is a pointer
   (`CNodeIsPointer`), tag the result `tyPointer` AND carry the pointer operand's
   element record/elem-tk on the binop node (needs a node-level pointer-elem
   slot, or reuse `ASTSOffset`/a parallel array — AN_IDENT uses `Syms[].PtrElemRec`,
   AN_INDEX resolves via `ResolveNodeRec`).
2. ParseCPostfix `->`/`.`: with the binop now pointer-typed, the existing
   `CNodeIsPointer` path inserts `AN_DEREF`; set that deref's carried record id
   (`ASTIVal[deref] := elemRec` — ResolveNodeRec already honours
   `ASTIVal[AN_DEREF] > 0`, symtab.inc ~4794) so `(p+i)->field` resolves the
   field offset and type.
3. Verify `p[i].field` (index form) and `(p+i)[j]` still work.

Common in lua/sqlite (stack/array element access). Use the full-file-bisection
harness (see the feature ticket) to confirm against lapi.c after fixing.
