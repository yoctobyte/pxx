---
slug: bug-c-a-pointer-to-an-array-typedef-of-pointers-has-no-shape
track: C
prio: 40
type: bug
status: backlog
created: 2026-11-20
found-by: pxx2, building libXt for the Path B JWM desktop
tags: [cfront, typedef]
blocked-by: []
summary: "`typedef RecPtr Table[16]; Table *pt = &tab; (*pt)[3]->f` segfaults (gcc: works). RecPtr is a pointer typedef, so the local path sees depth 2 (one level from RecPtr, one star), and the pointer-to-array-typedef arms read depth 2 as `T **` over an array typedef (the base pointee is the array). A pointer to an array OF POINTERS needs its own reading: one written star, pointee = the 16-pointer array."
---

# A pointer to an array typedef of pointers has no shape

Found while fixing
bug-c-an-array-typedef-of-pointers-is-read-as-a-pointer-to-the-array
(2026-11-20). That fix makes the typedef itself, plus globals, locals, fields
and parameters declared with it, match gcc. Before it, `Table` was a single
pointer, so this case was wrong already. It is not a regression.

Repro:

```c
typedef struct _Rec *RecPtr;
typedef struct _Rec { RecPtr next; long a[8]; } Rec;
typedef RecPtr Table[16];
static Table gtab;
int main(void) {
  static Rec r1; Table *pt = &gtab;
  r1.a[0] = 11; gtab[3] = &r1;
  printf("%ld %d\n", (*pt)[3]->a[0], (int)sizeof *pt);   /* gcc: 11 128 */
}
```

Where to look: ParseCLocalDeclAST's `declTk = tyPointer` arm, which stamps
SymPtrElemArrLen for `declPtrDepth` 1..2, and the global twin at
`gPtrD`. Count the WRITTEN stars (CTypeSpelledStars, added by the fix above),
not the depth.
