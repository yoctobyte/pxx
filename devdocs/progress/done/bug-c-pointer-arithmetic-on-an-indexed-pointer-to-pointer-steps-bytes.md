---
track: C
tags: [cfront, pointers, pointer-arithmetic, pathb, st]
prio: 75
type: bug
blocked-by: []
summary: "`(L[0] + 1)->fg` on `Glyph **L` (and `term.line[y] + x` on a `Line *line` field) stepped ONE BYTE: IRPointerStride had an arm for `*p + 1` on a T** but none for `p[i] + 1`, which fell to the size-1 default. Also in the v452 pin."
status: done
owner: pxx2
---

# Pointer arithmetic on an indexed pointer-to-pointer stepped bytes

ir.inc IRPointerStride has two new AN_INDEX arms:

- an identifier T** steps by T, from its recorded depth and base, the same
  as the AN_DEREF arm;
- a struct field whose pointee is a pointer over a record (fields record no
  depth) steps by that record.

Test: test/c_ptr_to_ptr_typedef.c (row c_pptd26) against gcc, x86-64 and i386.
