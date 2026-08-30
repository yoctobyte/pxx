---
slug: bug-c-sizeof-of-a-dereferenced-pointer-to-array-answers-the-element-size
track: C
prio: 45
type: bug
status: backlog
owner:
blocked-by: []
summary: "C: `sizeof(*p)` where `int (*p)[4]` answers 4 (the ELEMENT size) where gcc says 16 (the whole pointee). Silent wrong value, compiles clean, exit 0. Same for `int (*r)[4] = m` over an `int m[3][4]`. Pascal's equivalent `SizeOf(p^)` is CORRECT, so this is the C reader alone, not the metadata: SymPtrElemArrLen is populated and DerefPtrArrayInfo already answers the flat count for the Pascal side. Found while regression-checking a Track A fix to `p^[i]` indexing; measured byte-identical on the pinned compiler, so it is pre-existing and NOT a regression from that work."
---

# `sizeof(*p)` on a pointer-to-array answers the element size

## Measured

gcc 13 as the oracle, pxx at `3a53468cb267` and at the **pinned** binary —
identical, so this predates the Track A indexing fix that turned it up.

```c
int a[4]; int (*p)[4] = &a;
int m[3][4]; int (*r)[4] = m;
printf("%zu %zu\n", sizeof(*p), sizeof(*r));
```

| | gcc | pxx |
| --- | --- | --- |
| `sizeof(*p)` | 16 | **4** |
| `sizeof(*r)` | 16 | **4** |

Every other row of the same program agrees with gcc: `(*p)[1]`, `p[0][1]`,
`(*pc)[1]` on a `char (*)[4]`, `(*psp)[1]` on a `char *(*)[3]`, `(*prr)[1].a`
on a `struct R (*)[3]`, and the write `(*p)[2] = 99`. Only `sizeof` is wrong,
which is the tell that the shape is recognised and one reader is not.

## Why it is probably small

The metadata is present and the Pascal side already reads it correctly:
`SizeOf(p^)` over `^array[0..3] of Integer` answers 16, and over
`^array[0..1, 0..2] of Integer` answers 24 — both matching FPC. That path goes
through `DerefPtrArrayInfo`'s `flatCount` (`symtab.inc`), which is exactly the
product this needs and is already split out for reuse; `DerefPtrArraySym` beside
it hands back the symbol. So this looks like the C `sizeof` arm asking
`PtrElemTk`'s size without first asking whether `SymPtrElemArrLen > 0`.

**Do not assume that guess.** It is a reading of two functions, not a
measurement — the arm has not been found, let alone run.

## Why it is filed rather than fixed

Track C's gate is C tests + self-host + cross, and the session that found it
holds A/P. It is a one-line-ish read but it is in someone else's lane and their
gate is the one that would catch a mistake in it.
