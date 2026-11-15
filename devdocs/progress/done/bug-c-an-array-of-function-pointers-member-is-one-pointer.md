---
slug: bug-c-an-array-of-function-pointers-member-is-one-pointer
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat): ACPI INTx table, kernel page fault on q35; rump repro s12
tags: [cfront, silent-miscompile]
blocked-by: []
summary: "A struct member spelled `void (*fn[4])(void);` was laid out as ONE 8-byte pointer: ParseCStructInto's inline function-pointer arm ignored CTypeFnPtrArrLen. Every member after it overlapped the array, and `p->fn[i]` loaded fn as a pointer and indexed what it pointed at. The typedef spelling (`fn_t fn[4];`) was right. Now the arm records an array of N pointers with the element signature on bfProcSig, as the typedef path does. Test: test/c_fnptr_array_member.c (sizeof/offsetof, a union, an initialiser, `(*p->fn[i])()`; executable and gcc-linked object)."
---

# An array-of-function-pointers member was one pointer

The repro is Gibux's `struct s { unsigned gsi; void (*fn[4])(void); void *arg[4]; }`:
gcc gives size 72 with arg at 40, pxx gave 48 with arg at 16.
