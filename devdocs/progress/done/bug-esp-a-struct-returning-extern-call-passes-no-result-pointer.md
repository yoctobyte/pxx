---
track: ESP
tags: [C, esp, xtensa, freestanding, abi, gibux]
prio: 5
type: bug
blocked-by: []
summary: "In a freestanding xtensa object, a direct call to an extern function returning a struct passed no hidden result pointer. The callee is another pxx object and stores its result through that pointer: windowed it read whatever a10 held, and Gibux's mount_ns_root faulted on 0 (StoreProhibited). The direct-call gate excluded every external because it was written for gcc-built ESP-IDF routines; in an EspFreestandingObj build an external is pxx code, so it now gets the pointer (XtensaCallHasHiddenDest). Under call0 the literal-call sequence also loaded the callee into a8, over the destination; it now uses a9."
status: done
owner: unassigned
---

# A struct-returning extern call passed no result pointer

This was the first fault of the booted pxx-built Gibux/S3 kernel, reported by the Gibux kernel session. ramfs.o fs_root_path called mount_ns_root in fs/mount.c. The repro is `~/gibux-payload/pxx-repros/xtensa-2026-11-17/structret2.c` with `structret2g.c`.

## Two defects
1. **The gate (ir_codegen_xtensa.inc).** Three sites tested `not ProcExternal[procIdx]` before passing the hidden destination: the call0 push, the windowed word 0, and the call0 a8 load. They now ask XtensaCallHasHiddenDest, which also admits an external under EspFreestandingObj.
2. **a8 on call0 (symtab.inc, EmitCallProc).** The external literal call and the IRAM cross-call both did `l32r a8; callx0 a8`, and a8 is the call0 hidden-destination register. Both now use a9 under call0. The indirect path made the same move earlier.

Function pointers were already correct: IR_CALL_IND passes IRCallDest on both ABIs.

## Limit
Across a gcc boundary this is still not gcc's ABI. gcc returns a struct of 16 bytes or less in a2..a5. A pxx caller of a gcc-built struct-returning function, or the reverse, does not match yet. All of Gibux's C is pxx, and its .S files return no structs.

## Test
tools/check_xtensa_freestanding_struct.py runs test/c_xtensa_extern_structret_{a,b}.c under qemu-xtensa (call0). It covers 8- and 24-byte results, a direct call through a static wrapper, and calls through function pointers. The expected exit status, 32, is gcc's value. The script also compiles the windowed form. The old compiler crashes on the test.

riscv32 has the same gate (ir_codegen_riscv32.inc ~4721); see bug-c-struct-copy-and-zero-in-a-freestanding-riscv32-object.
