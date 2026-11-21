---
slug: bug-c-a-pointer-to-an-array-typedef-of-pointers-has-no-shape
track: C
prio: 40
type: bug
status: done
created: 2026-11-20
found-by: pxx2, building libXt for the Path B JWM desktop
tags: [cfront, typedef]
blocked-by: []
summary: "DONE 2026-11-21: `T *p` over an array typedef of pointers is a pointer to the whole array (depth 1, as `E *(*p)[N]`) in locals, globals and parameters; the local `T **` too. Test c_tdpap26. Residual filed: bug-c-a-pointer-to-a-pointer-to-an-array-typedef-of-pointers-loses-its-record. `typedef RecPtr Table[16]; Table *pt = &tab; (*pt)[3]->f` segfaults (gcc: works). RecPtr is a pointer typedef, so the local path sees depth 2 (one level from RecPtr, one star), and the pointer-to-array-typedef arms read depth 2 as `T **` over an array typedef (the base pointee is the array). A pointer to an array OF POINTERS needs its own reading: one written star, pointee = the 16-pointer array."
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

## Done, 2026-11-21 (claude-pxx)

**Measured first.** All six shapes in the repro were wrong, not only the
read: `(*pt)[3]` crashed in a local, a global and a parameter, `pt + 1`
stepped the wrong distance, `RecPtr *e = *pt` crashed, and the store
`(*pt)[7] = v` did not compile (IR_UNSUPPORTED, AN_DEREF). A pointer to a
typedef'd array of `long`s was fine. The explicit spelling `RecPtr (*pt)[16]`
was fine in every case, which gave the target.

**Cause.** The explicit spelling's symbol is depth 1 with pointee and base
`tyPointer` and the array length on the pointee. `Table *pt` arrived as
depth 2 (one level from the typedef's elements, one from the star) with the
struct as its base. Every reader takes that as `RecPtr *` over a base array
(the `mat4 **pp` reading).

**Fix (cparser.inc).** When an array typedef's elements are pointers and the
declarator wrote one star, the symbol gets the explicit spelling's triple:
- in the local path, using a new `lclStars` count of the stars written, kept
  per sibling in both comma blocks (the loop-tail block now also updates
  `lclNoStar`, which it left at the first declarator's value);
- in the global path, for the first declarator;
- in the parameter path.

A local `T **pp` with two written stars gets depth 2, base pointer, and the
array as the base pointee's shape, as `TL **pp` over longs has it.

**Test.** test/c_ptr_to_array_typedef_of_ptrs.c (c_tdpap26), against gcc on
x86-64, aarch64 and i386 (its own expected file: 4-byte pointers). It covers
local, global, parameter, `long *T[16]` and pointer-typedef elements,
siblings, a 2-D typedef, `T **`, stores and decay. The pinned compiler
cannot compile it.

**Not done, filed:**
bug-c-a-pointer-to-a-pointer-to-an-array-typedef-of-pointers-loses-its-record.
