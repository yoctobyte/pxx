---
slug: bug-c-a-pointer-to-a-pointer-to-an-array-typedef-of-pointers-loses-its-record
track: C
prio: 25
type: bug
status: backlog
created: 2026-11-21
found-by: claude-pxx (fixing bug-c-a-pointer-to-an-array-typedef-of-pointers-has-no-shape)
tags: [cfront, typedef]
blocked-by: []
summary: "Over `typedef RecPtr Table[16]` (an array of struct pointers): a local `Table **pp` indexes right, but `(**pp)[5]->a[1]` reads 0 (gcc: 22); through a typed temporary it works. `T **` in a GLOBAL or a PARAMETER is not handled at all (the depth-1 fix covers those, the local path alone covers depth 2). The explicit spelling `long *(**pq)[16]` does not parse ('expected C expression'). Rare shapes; none seen in real code yet."
---

# A pointer to a pointer to an array typedef of pointers loses its record

Left over from
done/bug-c-a-pointer-to-an-array-typedef-of-pointers-has-no-shape.md, which
fixed `T *p` everywhere and the local `T **pp`.

## Repro

```c
typedef struct _Rec *RecPtr;
typedef struct _Rec { RecPtr next; long a[8]; } Rec;
typedef RecPtr Table[16];
static Table gtab;
int main(void) {
  static Rec r2; Table *pt = &gtab; Table **ppt = &pt; RecPtr x;
  r2.a[1] = 22; gtab[5] = &r2;
  x = (**ppt)[5];
  printf("%ld %ld\n", x->a[1], (**ppt)[5]->a[1]);   /* gcc: 22 22, pxx: 22 0 */
}
```

`&(**ppt)[5] - gtab` is 40, as in gcc, so the indexing is right. What is lost
is the record on the element: `->` straight on `(**ppt)[5]` reads the wrong
offset. CPtrToArrShapeSym (ir.inc) answers only one `*` or `[i]` over an
identifier, and `**ppt` is two; the element record (CPtrToArrElemRec) comes
from somewhere else on this path.

## Also open

- `T **g` as a GLOBAL or a PARAMETER: only the local path has the depth-2
  rule (`lclStars`). The global path has its rule for `gSpelled = 1` only,
  and the parameter path for `CTypeSpelledStars = 1` only.
- The explicit `long *(**pq)[16]` is a parse error in pxx
  ("expected C expression" at `pq`). `long *(*q)[16]` parses.
