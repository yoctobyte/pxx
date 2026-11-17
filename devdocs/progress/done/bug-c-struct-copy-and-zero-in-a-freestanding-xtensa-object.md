---
track: ESP
tags: [C, esp, xtensa, freestanding, gibux]
prio: 20
type: bug
blocked-by: []
summary: "In a freestanding or bare xtensa object (EspBareBoot), zeroing an aggregate (= {0}, compound literals, hidden result temps) refused with 'PXXMemZero is provided by the builtinheap unit', and struct assignment or return by value stopped with 'compiler error: PXXMemMove not found'. Those helpers are RTL, which such an image does not have. They are now inline loops: words when the size is a multiple of 4 and both pointers are 4-aligned at run time, bytes otherwise. This hit 32 of the Gibux ESP32-S3 kernel's C files."
status: done
owner: unassigned
---

# Struct copy and zero in a freestanding xtensa object

Found by the first pxx build of the Gibux ESP32-S3 kernel (latest-6834cfbb55). It broke 21 files on PXXMemZero and 11 on PXXMemMove. The repros are `~/gibux-payload/pxx-repros/xtensa-2026-11-17/{zero,move}.c`.

## Fix
`XtensaInlineMem(n, isCopy)` in ir_codegen_xtensa.inc replaces the helper call when EspBareBoot is set. It is used at five sites:
- IR_DEFAULT_MEM
- IR_COPY_REC
- the hidden aggregate result temp
- the managed-local zero-init
- the aggregate-result epilogue in symtab.inc

The loop clobbers a2, a3 and a8..a11 only, which is what the call it replaces clobbers on both ABIs. It chooses between the word and byte loops at run time, because a struct of chars may be misaligned and an unaligned l32i/s32i faults. It copies forward only, since C struct assignment cannot partially overlap.

## Test
- test/c_xtensa_freestanding_struct.c, linked with test/c_xtensa_freestanding_start.S.
- tools/check_xtensa_freestanding_struct.py runs it under qemu-xtensa (call0) and compiles the windowed form. The expected exit status 81 is gcc's value.

riscv32 has the same gap: bug-c-struct-copy-and-zero-in-a-freestanding-riscv32-object.
