---
track: ESP
tags: [xtensa, riscv32, dce, size, busybox, gibux]
prio: 10
type: feature
blocked-by: []
summary: "Hosted (--platform=posix) xtensa and riscv32 objects now let DCE withhold unreferenced Pascal class slots, as ESP objects already did. Before, the always-present TInterfacedObject VMT rooted the whole release chain (PXXObjRelease, PXXRecordRelease, PXXDynArrayReleaseDepth, PXXVarReleasePayload, PXXTIOGetInterface, PXXIntfIMTOf, ...) in every C object, about 14 KB each. An empty TU's code goes from 18,084 B to 4,740 B; across BusyBox's 182 objects that was about 3.3 MB of the 5.4 MB pxx2 measured."
status: done
owner: unassigned
---

# Hosted ESP-family objects drop unreferenced class slots

pxx2 measured it while fitting BusyBox into Gibux's 8 MiB of PSRAM. coreutils/test_ptr_hack.c, an empty TU, had 17,936 B of text, mostly Pascal runtime as LOCAL symbols.

## Cause
`--dce-why` on `int f(int x){return x+1;}` showed 13.4 KB rooted by `[vmt/rtti slot]` through TInterfacedObject._Release and .QueryInterface. DceClassSlotsWithholdable allowed withholding only for PLATFORM_ESP objects, but its reasoning is about the xtensa/riscv32 object writers' reference tables, which hosted objects share.

## Fix
dce.inc: DceClassSlotsWithholdable also accepts PLATFORM_POSIX for xtensa and riscv32 objects.

## Result
- Empty TU: 18,084 B -> 4,740 B of code (live procs 29 -> 5).
- What remains is mostly the process entry stub's exit path (__pxx_atexit_run, PXXNilRef, PXXWriteNL, ~3.5 KB). It is reachable from the weak app_main that every posix object carries, though only main's object runs it. That is a follow-up.

## Test
The xtensa object checks (shared runtime with cross-object globals, posix main, PIE link, setjmp, vfork) pass. The xtensa suite runs too.
