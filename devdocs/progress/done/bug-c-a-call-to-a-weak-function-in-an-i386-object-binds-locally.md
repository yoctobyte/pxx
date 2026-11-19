---
slug: bug-c-a-call-to-a-weak-function-in-an-i386-object-binds-locally
track: C
prio: 35
type: bug
status: done
created: 2026-11-19
owner: claude-dupwt
tags: [cfront, emit-obj, link, weak, i386]
blocked-by: []
summary: "A call to a weak function definition in an i386 object was a resolved rel32 into the object's own copy, so another object's strong definition did not replace it (c_weak_a.o + c_weak_b.o printed 2, gcc 20). ObjBuildTextRelocs386 now gives such a call an R_386_PC32 against the callee's global symbol, with the REL addend -4 in the code word. The function half of bug-c-a-strong-definition-does-not-replace-a-weak-one-in-an-i386-object, which stays open for data."
---

# A call to a weak function in an i386 object binds locally: fixed

On x86-64 a call is relocated against its callee only under
--function-sections (ObjCallFixIsRelocatable), which the i386 writer does
not implement. The fix does not need it. In ObjBuildTextRelocs386 each
CallFix whose callee is a ProcCWeakDef with a global row (numbered as the
symbol table emits exported procedures) gets `Patch32(pos, -4)` and an
R_386_PC32 against that row. The relocations are built before .text is
written, so the patched addend is what lands in the file.

## Measured (tools/pxx_link_i386.sh)

| link | before | after | gcc / x86-64 objects |
| --- | --- | --- | --- |
| c_weak_a.o + c_weak_b.o | 2 -1 3 1 | 20 -1 3 1 | 20 -1 3 1 |
| c_weak_a.o alone | 2 -1 3 1 | 2 -1 3 1 | 2 -1 3 1 |

Row i386/c_weak386 in test-i386.
