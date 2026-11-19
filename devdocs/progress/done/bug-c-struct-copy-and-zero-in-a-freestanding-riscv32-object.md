---
track: ESP
tags: [C, esp, riscv32, freestanding]
prio: 50
type: bug
blocked-by: []
summary: "The riscv32 half of bug-c-struct-copy-and-zero-in-a-freestanding-xtensa-object. --target=esp32c3 --freestanding --emit-obj still refuses `struct x = {0}` with 'PXXMemZero is provided by the builtinheap unit' and struct assignment with 'compiler error: PXXMemMove not found'. Port XtensaInlineMem to the riscv32 codegen sites and to the riscv32 aggregate-result epilogue in symtab.inc."
status: done
owner: claude-dupwt
---

# Struct copy and zero in a freestanding riscv32 object

The xtensa fix (XtensaInlineMem) did not reach riscv32. Nilix targets the S3 only, so nobody is blocked on this yet.

## Repros
- `~/nilix-payload/pxx-repros/xtensa-2026-11-17/{zero,move}.c` built with `--target=esp32c3`.
- test/c_xtensa_freestanding_struct.c.

## Sites
- ir_codegen_riscv32.inc: IR_DEFAULT_MEM, IR_COPY_REC, and the hidden-temp zero and managed-local zero.
- symtab.inc: the riscv32 aggregate-result epilogue.

## Also: struct return from an extern callee (2026-11-17)
ir_codegen_riscv32.inc gates the hidden result pointer on `not ProcExternal[procIdx]` (~4721, ~4979, ~5009). This is the same defect bug-esp-a-struct-returning-extern-call-passes-no-result-pointer fixed on xtensa. In a freestanding riscv32 object an extern callee is pxx code and needs the pointer. Port XtensaCallHasHiddenDest. test/c_xtensa_extern_structret_{a,b}.c is the shape to test with.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).


# Fixed 2026-11-19 (claude-dupwt)

Both halves, ported from xtensa:

- **Rv32InlineMem** (ir_codegen_riscv32.inc), XtensaInlineMem's twin. Under
  EspBareBoot (a bare image or a freestanding object, neither of which has an
  RTL), IR_DEFAULT_MEM, IR_COPY_REC, the hidden-temp zero, the managed-local
  zero and the aggregate-result epilogue (symtab.inc) copy or zero inline.
  Words when n is a multiple of 4 and both pointers are aligned at run time,
  bytes otherwise.
- **Rv32CallHasHiddenDest**: an extern callee in a freestanding object gets
  the hidden result pointer in t1. The push, the call and the pop all ask it,
  so they agree.

Measured with Espressif's riscv32 binutils and qemu-riscv32 user mode
(tools/check_riscv32_freestanding_struct.py, a new row beside the xtensa
one, using test/c_riscv32_freestanding_start.S):

| test | published compiler | after | gcc rv32imc -O0 |
| --- | --- | --- | --- |
| c_xtensa_freestanding_struct.c | does not compile (PXXMemZero) | 81 | 81 |
| c_xtensa_extern_structret_{a,b}.c | does not compile | 32 | 32 |

The link needs --no-relax: _start never sets gp, and with relaxation even
gcc's own object segfaulted. That was the harness, not the code.
