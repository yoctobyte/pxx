---
slug: bug-c-an-element-of-a-pointer-to-an-array-of-pointers-has-no-pointee-type
track: C
prio: 30
type: bug
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (fixing bug-c-a-pointer-to-a-pointer-to-an-array-typedef-of-pointers-loses-its-record)
tags: [cfront, pointer-to-array]
blocked-by: []
summary: "Over `short *(*q)[16]` (or `typedef short *T[16]; T *q`), `*(*q)[5]` loads 8 bytes where gcc loads a short (pxx 6488141, gcc 77). A pointer and a long are both 8 bytes, so `long *` elements only look right. Separately, `&(*pt)[5] - gtab` is 0 (gcc 5): the difference divides by sizeof the whole array. Through a `T *e` temporary both are right. Struct-pointer elements were fixed in the parent ticket."
---

# An element of a pointer to an array of pointers has no pointee type

## Repro

```c
#include <stdio.h>
static short *lt[16];
static short v[2] = {77, 99};
int main(void) {
  short *(*q)[16] = &lt;
  lt[5] = v;
  printf("%d\n", *(*q)[5]);                 /* gcc 77, pxx 6488141 */
  printf("%d\n", (int)(&(*q)[5] - lt));     /* gcc 5, pxx 0 */
  return 0;
}
```

The same happens one level up (`short *(**pq)[16]`, `(**pq)[5]`) and
through a typedef (`typedef short *T[16]; T *p`).

## Cause, as far as measured

A pointer to an array of pointers is stamped depth 1, with the pointee and
the base both `pointer` (SetSymPointerType in the local, global and
parameter paths, and the `elem (*name)[N]` declarator arm). The element's
own pointee type (`short`) is recorded nowhere. CNodePointeeTk's AN_INDEX arm
then answers `pointer` for `(*q)[5]`, so the `*` loads 8 bytes.

For a struct element the parent ticket answers from CPAElemRec, which does
carry the record. A scalar needs a slot for the element's pointee type.

The difference `&(*q)[5] - lt` probably takes its stride from the AN_ADDR
arm (CAddrOfArrayShape), which sizes the whole pointee array (128) and not
the element (8). Not measured further.

## Who needs it

No known user. Seen only while testing the parent ticket's shapes.

## Done (2026-11-22)

- **The element's pointee type.** A new per-symbol slot,
  SymPtrArrElemPteTk, holds it. It is filled for the explicit spelling,
  through CTypePtrArrElemPteTk which the `elem (*name)[N]` arm takes before
  it overwrites the type, and for the typedef rules from the base type they
  replace. That covers the local, global and parameter paths, depth 1 and
  depth 2. CPtrShapeFromSym carries the slot into CPAElemPteTk, and
  CNodePointeeTk's AN_INDEX arm answers from it.
- **The difference.** IRPointerStride's `&x[i]` arm took IRArrayElemStride
  of the base, which for a pointer-to-array base is the whole array. Over
  such a base (CPtrToArrShape) the element is the shape's element.

Test c_pointer_to_array_of_pointers_element (gcc-checked: x86-64, i386,
aarch64, riscv32). It covers short and char elements, the explicit and
typedef spellings at depth 1 and 2 as local, global and parameter, and
differences over int, short-pointer, struct and 3-D pointees.
