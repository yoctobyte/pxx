---
slug: feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-installed
track: S
type: feature
prio: 60
status: backlog
owner: ""
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: "A raw hardware ISR cannot be INSTALLED from PXX on either ESP ISA, so the `interrupt;` directive -- whose codegen is complete and verified correct on both -- has no reachable execution path and has never been entered by a trap on any instrument. The gap is one instruction class: writing `mtvec` (riscv32) or `vecbase` (xtensa). Measured 2026-09-21 at pin v414, all spellings: `csrw mtvec, t0` -> asm: unknown symbol mtvec; `csrw 0x305, t0` -> the asm operand lexer splits the hex literal into `0` and `x305`; `csrw 773, t0` -> parses as a mnemonic and reaches EmitAsmRv32, which has no encoding for it; `wsr a4, vecbase` -> same failure on xtensa. The tree's ONLY CSR write is rv32_csrw_mstatus (rv32enc.inc:161), hardwired to mstatus for the interrupt-disable the atomics use, so the capability exists at the encoder level and is not reachable from source. ir_codegen_riscv32.inc:1654 documents IR_PROCADDR's own purpose as `needed for raw ISR install (mtvec)` -- the handler's address is obtainable and not installable, i.e. the feature is complete at both ends and missing one instruction in the middle. THIS IS THE ROW THAT MOVES INTERRUPTS FROM UNTESTABLE TO QEMU-TESTABLE: it needs no board, and until it lands, any interrupt work that is not the esp_intr_alloc/`iram;` path cannot be verified by anyone, including the owner on silicon. A separate smaller bug falls out and is worth fixing regardless: the inline-asm operand lexer does not accept hex literals."
---

# No CSR/special-register write is expressible, so no raw ISR can be installed

## What is already correct

`interrupt;` codegen is complete on both ESP ISAs — verified by disassembly at
pin v414 (`--emit-obj`, `test/test_esp_interrupt.pas`): full caller-saved
save/restore, `.iram1.text` placement, and the right trap-return instruction
(`mret` on riscv32, `rfe` on xtensa Call0). Nothing about the handler needs
work.

## What is missing

The install. Four spellings, all measured, none working:

    csrw mtvec, t0     asm: unknown symbol: mtvec
    csrw 0x305, t0     asm: unknown symbol: x305      (hex literal split by the lexer)
    csrw 773, t0       EmitAsmRv32: unsupported instruction
    wsr  a4, vecbase   asm: unknown symbol: vecbase   (xtensa)

`csrw` is recognised as a mnemonic — it reaches the emitter — so this is a
missing encoding, not a missing parser. `rv32enc.inc:161` already has
`rv32_csrw_mstatus`, used by the atomics' interrupt-disable, which is the
same instruction with the CSR number frozen.

## Why it matters beyond tidiness

`devdocs/dev/esp32-hardening-map.md` orders ESP work by **who can answer a
row**. This row is the one that moves the owner's stated must-have from
*answerable by nobody* to *answerable in qemu on this box*. ESP-IDF and
Espressif qemu for both ISAs are installed on plexus; the only thing missing
between here and a fixture that installs a vector, takes a deliberate trap and
asserts the handler ran is this instruction. It never becomes a board question.

## Two things for whoever takes it

1. **A named-CSR table is a nicety; the numeric form is the capability.** If
   only one lands, make it the numeric one — but then the hex-literal lexer bug
   must land with it, or the only usable spelling is decimal, which nobody
   writes for a CSR address.
2. **A design question this exposes, and it is not an implementation detail.**
   An `interrupt;` routine has no way to adjust the return address, so for a
   *synchronous* trap (`ecall`, illegal instruction, load fault) `mret` returns
   to the faulting instruction and re-faults forever. The directive is
   asynchronous-only and nothing in its surface says so. Decide whether that is
   the intended scope before building a fixture that traps synchronously —
   otherwise the first test written against this will hang, correctly, and read
   as a defect in the new code.

## Related

- `bug-s-an-interrupt-directive-proc-reached-through-a-normal-call-returns-via-mret-with-no-diagnostic`
  — the sibling hazard; its refusal is cheap *because* this ticket is open.
- `devdocs/dev/esp32-hardening-map.md` §1.1.
