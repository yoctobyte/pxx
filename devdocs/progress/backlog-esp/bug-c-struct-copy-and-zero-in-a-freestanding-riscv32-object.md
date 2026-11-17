---
track: ESP
tags: [C, esp, riscv32, freestanding]
prio: 50
type: bug
blocked-by: []
summary: "The riscv32 half of bug-c-struct-copy-and-zero-in-a-freestanding-xtensa-object. --target=esp32c3 --freestanding --emit-obj still refuses `struct x = {0}` with 'PXXMemZero is provided by the builtinheap unit' and struct assignment with 'compiler error: PXXMemMove not found'. Port XtensaInlineMem to the riscv32 codegen sites and to the riscv32 aggregate-result epilogue in symtab.inc."
status: open
owner: unassigned
---

# Struct copy and zero in a freestanding riscv32 object

The xtensa fix (XtensaInlineMem) did not reach riscv32. Gibux targets the S3 only, so nobody is blocked on this yet.

## Repros
- `~/gibux-payload/pxx-repros/xtensa-2026-11-17/{zero,move}.c` built with `--target=esp32c3`.
- test/c_xtensa_freestanding_struct.c.

## Sites
- ir_codegen_riscv32.inc: IR_DEFAULT_MEM, IR_COPY_REC, and the hidden-temp zero and managed-local zero.
- symtab.inc: the riscv32 aggregate-result epilogue.
