---
slug: bug-c-sizeof-of-a-pointer-to-array-struct-field-answers-the-pointer-size
track: C
prio: 40
type: bug
status: done
owner: frankC
blocked-by: []
summary: "DONE. `sizeof(*s.fp)` where `fp` is a struct member of type `int (*)[4]`. The ticket recorded 8 (the pointer size); by the tree this was fixed on it answered 4, and 4 is NOT the element size -- it is TypeStorageSize(tyUnknown), i.e. the field held no pointee at all. The int spelling cannot tell those apart because the tyUnknown default equals sizeof(int); `double (*dp)[4]` answering 4 rather than 8 is what separates them, and is why the test carries int, double, char and a 2-D row. Cause is the SAME arm as bug-c-a-file-scope-pointer-to-array-crashes-on-indexing one scope down: the C struct builder's parenthesised-declarator member arm was written for FUNCTION pointers, whose pointee has no type, and hardcoded tyUnknown -- but `int (*fp)[4]` reaches it too, since ParseCDeclType parks the name in CTypeFnPtrName for both shapes. Third instance of one omission (local records it and works; global and field did not). Needed BOTH halves, where the ticket named one: the pointee TYPE from CTypeElemTk/Rec, plus a genuinely new UFldPtrElemArrLen column -- the field twin of SymPtrElemArrLen, flattened so `int (*)[2][3]` needs no second rule -- wired through EnsureUFieldCapacity, AddUField's two resets, the class-inheritance copy and the C emit loop. Verified against measured strides, never constants; positive control on the pinned binary fails 11 rows."
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

## Root cause, 2026-09-02 — and the ticket's own measurement had gone stale

**The `8` above is no longer what pxx answers, and the diagnosis built on it
was wrong.** At the tree this was fixed on, `sizeof(*s.fp)` answered **4**, and
4 is not the element size either — it is `TypeStorageSize(tyUnknown)`. The
field held **no pointee at all**.

The int spelling cannot tell those apart, and that is the whole reason this sat
misdiagnosed: `tyUnknown`'s default is 4, which is exactly `sizeof(int)`, so
the row reads like a plausible "element size" answer from a working arm. One
row settles it —

```
struct S { int (*ip)[4]; double (*dp)[4]; char (*cp)[7]; };
            pxx   gcc
sizeof(*s.ip)   4    16
sizeof(*s.dp)   4    32      <- not 8 either: the pointee TYPE is absent
sizeof(*s.cp)   4     7
```

`double` answering 4 rather than 8 is what says "nothing recorded" instead of
"element size recorded, extent missing".

**The cause is the same arm as
[[bug-c-a-file-scope-pointer-to-array-crashes-on-indexing]], one scope down.**
The C struct builder's parenthesised-declarator arm (`cparser.inc`, the
`CTypeFnPtrName <> ''` member arm) was written for FUNCTION pointer members,
whose pointee genuinely has no type, so it hardcodes `bfElemTk := tyUnknown`.
`int (*fp)[4]` reaches it because ParseCDeclType parks the name in
`CTypeFnPtrName` for both shapes. Third instance of one omission: the local
path records the pointee and works, the global path did not (fixed
`7d6559cd3`), the field path did not (fixed here).

So this needed BOTH halves, and the ticket's "Suggested shape" only named one:
- the pointee TYPE, from `CTypeElemTk`/`CTypeElemRec` in that arm;
- the extent, in a genuinely new column `UFldPtrElemArrLen` — the field twin of
  `SymPtrElemArrLen`, carrying the flattened product so `int (*)[2][3]`
  needs no second rule. Wired through EnsureUFieldCapacity, AddUField's two
  resets, the class-INHERITANCE copy, and the C emit loop, per the write-site
  list `UFldPtrElemStrTk`'s own comment records.

## Verified

`test/c_sizeof_ptr_to_array_field.c` (+ `.expected`). Sizes are asserted
against each pointer's MEASURED stride and against the real array pointed at,
never a spelled-out constant; `int`, `double`, `char` and a 2-D pointee are all
present precisely because a suite of int rows here is a guard that cannot fail,
and two rows assert that the pointees do NOT all agree. `plain`/`dplain` are
the in-test controls for a non-array pointee.

Positive control against the **pinned** compiler: 11 rows FAIL, while both
plain-pointer controls pass. Post-fix pxx and gcc both print
`FIELD PTRARR OK 16 32 7 24`. `gate.sh quick` GREEN, FPC seed canary PASS.

Note the pinned binary also fails the `(*s.ip)[1] = 77` addressing row that this
ticket recorded as correct on 2026-08-30 — pinned is not the tree that was
measured then, so that is not evidence the original reading was wrong. It is
correct at the fixed tree, which is what the row is there to hold.

Row G of the same probe — `sizeof(bp2[0][0])`, subscripting a
pointer-to-pointer — is untouched and stays with
[[bug-c-sizeof-reaches-a-pointee-through-one-spelling-only]].

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1769ac004.
