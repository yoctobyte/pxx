---
slug: bug-c-sizeof-of-a-pointer-to-array-struct-field-answers-the-pointer-size
track: C
prio: 40
type: bug
status: new
owner: ""
blocked-by: []
summary: "`sizeof(*s.fp)` where `fp` is a struct member of type `int (*)[4]` answers 8 -- the POINTER size, i.e. the arm never fired at all -- where gcc says 16. The VARIABLE spelling of the same construct is fixed; this is the field spelling, and it is NOT the same one-line gap: 8 rather than 4 says `RecFieldType(recId, 'fp') = tyPointer` is false or the pointee type is unrecorded, so the field arm declines before any extent could be applied. INDEXING through the same field is CORRECT -- `(*s.fp)[1]` reads and writes fine -- so the field carries enough to address and not enough to size, and a fix needs the pointee's extent on the FIELD (there is no UFldPtrElemArrLen; the symbol side has SymPtrElemArrLen)."
---

# `sizeof(*s.fp)` on a pointer-to-array struct member answers the pointer size

- **Filed:** 2026-08-30 by frankA, while fixing the VARIABLE spelling
  (`c_sizeof_deref_ptr_to_array.c`, landed with a gcc-oracle test).
- **Pre-existing:** `pinned` gives the identical answers.

## Measured, gcc as oracle

```c
struct S { int (*fp)[4]; int *plain; int (*fp2)[2][3]; };
...
sizeof(*s.fp)     pxx 8    gcc 16
sizeof(*s.fp2)    pxx 8    gcc 24
sizeof(*s.plain)  pxx 4    gcc 4     <- control: a plain pointer FIELD is right
sizeof(s.fp)      pxx 8    gcc 8     <- control: the pointer itself
(*s.fp)[1] = 77   pxx 77   gcc 77    <- control: INDEXING the field is right
```

## Why it is not the fix that just landed

The variable arm answered the **element** size (4). This field arm answers **8**,
the default pointer size, which means it never assigned `sz` at all — the
`if (recId <> REC_NONE) and (RecFieldType(recId, fieldName) = tyPointer)` test in
`cparser.inc`'s `sizeof(*...)` handler declines. So multiplying by an extent
there would change nothing; the field's pointee type has to be reachable first.

The indexing row is what makes this interesting rather than obvious: the field
**can** be dereferenced and subscripted correctly, so the shape is known
somewhere. Sizing reads a different set of metadata than addressing does.

## Suggested shape

The symbol side keeps `SymPtrElemArrLen` (flattened product for a multi-dim
pointee) beside `Syms[].PtrElemTk`. Fields have `UFldPtrElemTk`/`UFldPtrElemRec`
and **no** extent column. Establish first WHY the `= tyPointer` test fails for
`int (*fp)[4]` and succeeds for `int *plain` — that answer decides whether this
is one missing column or a C declarator-parsing gap wearing a sizeof mask.

## Related

- `bug-c-sizeof-of-a-dereferenced-pointer-to-array-answers-the-element-size` — the
  variable spelling, fixed the same day.
- The Pascal family of the same ambiguity:
  [[bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds]]
