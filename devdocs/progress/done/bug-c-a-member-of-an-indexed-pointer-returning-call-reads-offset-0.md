---
track: A
tags: [C, gibux]
prio: 80
type: bug
blocked-by: []
summary: "`f(x)[i].member` on a call returning a struct pointer read and wrote the member at offset 0. Through a function pointer, `fp()[i]` also stepped by bytes. Gibux ext4 lost data in files past 4 extents."
status: done
owner: claude
---

# A member of an indexed pointer-returning call reads offset 0

Reported by the Gibux session on 2026-11-13. fs/ext2.c's
`ext_index(p[l].h)[p[l].pick].leaf_lo` read `.block`, so ext4 files with
more than 4 extents lost data. The kernel was built with pxx at 29daf84560.
`x[0].leaf_lo` (through a variable) and `index_of(r)->leaf_lo` were right.

There were three defects:

1. ResolveNodeRec's AN_INDEX arm handled a CALL base with
   ResolveNodeRec(call). That is right for a Pascal array-returning call,
   whose ProcRetRecId is the element record. A C call returning `struct S *`
   has no record of its own; the indexed element's record is
   ProcRetPtrElemRec. The arm answered REC_NONE, so the member landed at
   offset 0, for reads and stores alike.
2. IRPointerStride had no AN_CALL_IND arm, so `fp()[1]` stepped by the
   1-byte default.
3. A function-pointer signature recorded its pointee only for struct
   pointers, so `int *(*)(void)` results were indexed by bytes as well:
   `fi()[2]` read 393216.

Test: test/c_index_of_a_pointer_returning_call.c is checked against gcc.
The base compiler got 12 of its 14 values wrong. The frozen latest compiler
behaves the same, so this is not a regression.
