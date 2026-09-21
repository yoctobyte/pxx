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
summary: "A raw hardware ISR cannot be INSTALLED from PXX on either ESP ISA, so the `interrupt;` directive -- whose codegen is complete and verified correct on both -- has no reachable execution path and has never been entered by a trap on any instrument. The gap is one instruction class: writing `mtvec` (riscv32) or `vecbase` (xtensa). Measured 2026-09-21 at pin v414, all spellings: `csrw mtvec, t0` -> asm: unknown symbol mtvec; `csrw 0x305, t0` -> the asm operand lexer splits the hex literal into `0` and `x305`; `csrw 773, t0` -> parses as a mnemonic and reaches EmitAsmRv32, which has no encoding for it; `wsr a4, vecbase` -> same failure on xtensa. The tree's ONLY CSR write is rv32_csrw_mstatus (rv32enc.inc:161), hardwired to mstatus for the interrupt-disable the atomics use, so the capability exists at the encoder level and is not reachable from source. ir_codegen_riscv32.inc:1654 documents IR_PROCADDR's own purpose as `needed for raw ISR install (mtvec)` -- the handler's address is obtainable and not installable, i.e. the feature is complete at both ends and missing one instruction in the middle. THIS IS THE ROW THAT MOVES INTERRUPTS FROM UNTESTABLE TO QEMU-TESTABLE: it needs no board, and until it lands, any interrupt work that is not the esp_intr_alloc/`iram;` path cannot be verified by anyone, including the owner on silicon. A separate smaller bug falls out and is worth fixing regardless: the inline-asm operand lexer does not accept hex literals. AND THE INSTALL IS NOT THE WHOLE JOB -- ADDED 2026-09-21 AFTER MEASURING THE TRAMPOLINE: a raw vector entry bypasses rtos_int_enter, which is what installs EVERY ISR facility the IDF provides -- both the nesting counter xPortInIsrContext reads and the SP switch to a dedicated ISR stack (portasm.S:643-645). So a raw handler runs on the interrupted TASK's stack (3584 bytes by IDF default, per defs.inc:2322) while pushing 64 bytes of prologue on riscv or 48 on xtensa, and reports xPortInIsrContext = 0 so the obvious safety check says all-clear. PXX has NO runtime stack guard on ESP on either profile (measured); the only protection is the build-time CheckBareImageFitsSram. LANDING THE CSR WRITE ALONE THEREFORE SHIPS A LOADED GUN -- it makes installable a handler that is unprotected by everything the platform does for ISRs, and the failure mode is a plausible wrong value far from its cause with the diagnostic reporting green. The stack story belongs in this ticket, not after it -- AND SO DOES THE ALLOCATOR STORY: on bare, PXXAlloc takes no lock under any flag (--threadsafe is REFUSED on both ESP ISAs), so the free list is safe only because nothing can currently interrupt it, and installing a raw ISR is precisely what ends that. Not escalated as a Track U fork because an existing goal already decides it: --esp-profile=bare exists deliberately and is a self-contained no-IDF image, so bare-metal raw ISRs are wanted, and what follows is engineering."
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

## The install is not the whole job — added 2026-09-21

See `devdocs/dev/esp32-hardening-map.md` §1.7. `rtos_int_enter` is what gives an
IDF-dispatched handler its safety properties, and a raw vector entry never
reaches it:

    portasm.S:598-605   port_uxInterruptNesting[coreID] += 1    { xPortInIsrContext reads this }
    portasm.S:643-645   lw sp, (xIsrStackTop[coreID])           { SP -> dedicated ISR stack }

A raw handler therefore runs on the interrupted task's stack and reports
itself as not-in-an-ISR. **Do not land the CSR write on its own.** Whatever
prologue an installed raw handler gets has to establish its own stack, or the
feature's first real use is a silent overflow into whatever is below that
task's stack.

**Suggested acceptance, so this cannot be forgotten at review:** the fixture
that first installs a vector must also assert the handler ran on a stack
OUTSIDE the interrupted task's stack bounds — not merely that it ran.

## And a SECOND thing it must carry — added 2026-09-21

`devdocs/dev/esp32-hardening-map.md` §1.6. On the **bare** profile `PXXAlloc`
backs onto the `EspArena` free list and **takes no lock under any flag**:
the codegen hard lock is `ThreadSafeMode AND TARGET_X86_64`
(`frontend_prologue.inc:127`), and `PXX_TS_SOFTLOCK` covers only
i386/aarch64/arm32 (`paslexer.inc:1226`). riscv32 and xtensa are in neither.
`--threadsafe` is **refused** on those targets, so there is no flag that fixes
it.

Today that is safe **by unreachability**: bare has no FreeRTOS, so the only
possible concurrency is an interrupt, and no interrupt handler can be installed
— which is this ticket. **Landing the install makes an unlocked allocator
concurrently reachable for the first time.**

So the enabler has two dependants, not one: the stack story above, and this.
Neither is optional and neither is visible from the CSR encoding itself.

## Related

- `bug-s-an-interrupt-directive-proc-reached-through-a-normal-call-returns-via-mret-with-no-diagnostic`
  — the sibling hazard; its refusal is cheap *because* this ticket is open.
- `devdocs/dev/esp32-hardening-map.md` §1.1.
