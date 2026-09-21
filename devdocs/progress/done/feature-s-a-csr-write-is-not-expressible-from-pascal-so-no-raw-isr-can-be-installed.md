---
slug: feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-installed
track: S
type: feature
prio: 60
status: done
owner: ""
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: "DELIVERED FOR riscv32 2026-09-21; THE XTENSA SIBLING IS SPLIT OUT TO feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-stack. A raw hardware ISR can now be installed AND ENTERED on bare riscv32, which it never could on any instrument before: `interrupt;` codegen was complete and unreachable, so no trap had ever entered a PXX handler. Three things landed together because none of them is useful alone. (1) CSR ACCESS: csrw/csrr/csrs/csrc/csrrw/csrrs/csrrc with a numeric CSR, plus mret, which had an encoder and no reachable spelling -- so a raw handler could not have RETURNED even once a vector could be installed. All eight forms diffed against riscv32-esp-elf-as, byte-identical (csrw mtvec,t0 = 30529073); AsmRv32CheckCsr checks rather than masks, because rv32_csr masks to 12 bits and an out-of-range address would otherwise silently address a DIFFERENT CSR in a well-formed instruction ($fff accepted, $1000 and -1 refused). (2) THE ISR STACK: the `interrupt;` prologue switches to a dedicated stack before pushing anything, via an mscratch round-trip -- a trap arrives with NO free register, which is the difficulty mscratch exists to solve; bare has no FreeRTOS so mscratch is ours, the IDF port uses it, hence the EspBareBoot gate. Carved from the top 1 KiB of the SRAM stack region rather than reserved in BSS, because the entry stub sets sp from a compile-time constant emitted BEFORE the body is parsed, so a BSS region would have to be unconditional -- the 64-KiB-arena-that-nothing-read mistake. (3) THE ir.inc @<interrupt proc> REFUSAL IS NARROWED, NOT DELETED, on the exact axis it argues from: its hazard is `would run on the interrupted code`s stack with no ISR stack`, now false for bare riscv32 and only there. Measured: xtensa bare REFUSED, riscv32 IDF REFUSED (also the esp_intr_alloc `interrupt;`-instead-of-`iram;` mistake, the commonest way to reach it), riscv32 bare PERMITTED. TWO FIXTURES, BOTH BYTE-IDENTICAL TO THE x86-64 ORACLE AND WIRED INTO test-esp-bare: test_esp_bare_csr.pas (hand-written handler, mtvec written and read back, two ecalls) and test_esp_bare_isrstack.pas (a real `interrupt;` handler). THE SECOND ASSERTS THE STACK AND NOT THE ENTRY, AND THE CONTROL IS THE REASON: with both switch sites disabled, `isr hits 2` stays GREEN while the stack row reddens -- `the handler ran` is true in both worlds and cannot distinguish them, and since stacks grow down a build without the switch necessarily lands on the far side of `isrSp > taskSp`. After restoring, the compiler binary came back byte-identical (84f93baa3bb4), which is how the revert was known to be complete. NO PIN NEEDED: esp_run_bare.sh builds with HEAD. gate.sh quick GREEN twice, self-host fixedpoint and FPC seed canary included; test_esp_bare and test_esp_bare_atomic still green on BOTH chips. A CONSEQUENCE WORTH CARRYING: this FIRES the trigger in frankh-c0`s feature-n-a-non-allocating-restricted-thunk-for-an-isr -- an allocator-reaching body can now be installed as a handler on bare riscv32 from Pascal, which it could not this morning. HEX WAS NEVER A BLOCKER AND THIS TICKET CLAIMED OTHERWISE FOR A DAY: Pascal `$305` works and is general; only C-style `0x305` is refused, split by the inline-asm tokenizer into `0` and the identifier `x305`."
---

# No CSR/special-register write is expressible, so no raw ISR can be installed

## What is already correct

`interrupt;` codegen is complete on both ESP ISAs — verified by disassembly at
pin v414 (`--emit-obj`, `test/test_esp_interrupt.pas`): full caller-saved
save/restore, `.iram1.text` placement, and the right trap-return instruction
(`mret` on riscv32, `rfe` on xtensa Call0). Nothing about the handler needs
work.

## WHAT LANDED 2026-09-21 — read this before the historical sections below

The riscv32 half. `compiler/rv32enc.inc` grew a general `rv32_csr` plus
`csrrw/csrrs/csrrc/csrrci` wrappers, and **the two hardwired mstatus helpers
are now DERIVED from them** rather than restating the encoding — `$300`
previously appeared in two instruction words that no test related to each
other. `compiler/asmtext_rv32.inc` accepts `csrw/csrs/csrc` (CSR first
operand, decided *before* the unconditional `AsmRv32RegOp` that used to raise
"expected register"), `csrr`, the three-operand `csrrw/csrrs/csrrc`, and
`mret` — which had an encoder and no way to reach it, so a raw handler could
not have RETURNED even once the vector could be installed.

**All eight forms were diffed against `riscv32-esp-elf-as` and match
byte-for-byte**, `csrw mtvec,t0` = `30529073`. `AsmRv32CheckCsr` rejects
outside 0..4095 — checked and not masked, because `rv32_csr` masks to 12 bits
and an out-of-range address would otherwise silently address a *different*
CSR in a well-formed instruction. Boundary measured: `$fff` accepted, `$1000`
and `-1` refused.

**`test/test_esp_bare_csr.pas` is the first thing in the tree to take a
trap.** It writes mtvec, reads it straight back, and takes two `ecall`s
through a hand-written handler that steps mepc and `mret`s. Byte-identical to
the x86-64 oracle; wired into `test-esp-bare`; the pinned compiler cannot
build it. `gate.sh quick` GREEN including the self-host fixedpoint.

**The regression risk I took deliberately** — deriving the mstatus helpers —
was controlled by running `test_esp_bare_atomic.pas` under qemu with the
pinned *and* HEAD compilers: both match the oracle. The riscv32 atomics mask
interrupts through exactly those two helpers, so that is the behavioural
control, not a byte comparison.

**No pin is needed.** `esp_run_bare.sh` builds with HEAD.

## What was missing — the measurement that opened this ticket

Five spellings, all measured, none working at the time — measured at
`ed1c3dfe6`, binary `497489e8a723`. **Rows 1-4 are now fixed; row 5 (xtensa)
is not.**

    csrw mtvec, t0     asm: unknown symbol: mtvec
    csrw 0x305, t0     asm: unknown symbol: x305      (C hex; see the note below)
    csrw $305, t0      EmitAsmRv32: expected register
    csrw 773, t0       EmitAsmRv32: expected register
    wsr  a4, vecbase   asm: unknown symbol: vecbase   (xtensa)

**The `$305` row is the one that names the gap, and it is why the hex question
is a distraction**: the Pascal hex spelling gets all the way through the
tokenizer and the integer parser and then fails for the real reason — `csrw`'s
FIRST operand is parsed as a register (`AsmRv32RegOp`, asmtext_rv32.inc:65-69,
which is what raises `expected register`), and a CSR address is not one. The
decimal spelling fails identically, which is the control: this is not about how
the number is written.

`csrw` is recognised as a mnemonic — it reaches the emitter — so this is a
missing encoding and an operand-class mismatch, not a missing number parser. `rv32enc.inc:161` already has
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
   only one lands, make it the numeric one. **Nothing has to land with it** —
   this ticket said otherwise for a day and was wrong, see the correction in
   the summary. `csrw $305, t0` is the spelling to write: `$` is Pascal hex,
   the text assembler's own integer parser takes it, and it is general.

   **The `0x` band is worth knowing about and is NOT a silent-wrong-value
   hazard, which is the reading to head off.** `0xNN` is accepted exactly when
   the tail spells a valid RISC-V register — decimal digits, value ≤ 31 — and
   refused otherwise, because the tokenizer is asking `AsmRv32RegNum`
   (asmtext_rv32.inc:48-60) about the identifier it split off. Measured at
   `ed1c3dfe6`, operand of `addi t0, t0, <v>`, read back by disassembling
   `Inst` through its own `nm` address:

       0x9 -> 9    0x11 -> 17   0x19 -> 25   0x25 -> 37   0x30 -> 48   0x31 -> 49
       0x1f -> refused   0x32 -> refused   0x40 -> refused   0xff -> refused
       0x305 -> refused

   **In the accepted band the value is the correct HEX value, not the register
   index** — `0x11` is 17 and not 11, `0x25` is 37 and not 25 — because the
   operand text is reassembled and re-parsed by `AsmTextParseInt`, which does
   handle `0x`. So every outcome is either right or loud, and a `0x` CSR
   address (all ≥ `0x300`) lands squarely in the loud half. The two readings
   collide for `0x9` and below, which is why the discriminating rows are the
   ones quoted.

   **The instrument that got this wrong first is worth recording**: a
   `grep addi.*t0,t0` over the WHOLE object answered `-80` for every row
   including the decimal controls, because it matched RTL prologue code and
   never my instruction. It agreed with itself across seven spellings, which
   read as stability. Window the disassembly to the symbol.
2. **A design question this exposes, and it is not an implementation detail.**
   An `interrupt;` routine has no way to adjust the return address, so for a
   *synchronous* trap (`ecall`, illegal instruction, load fault) `mret` returns
   to the faulting instruction and re-faults forever. The directive is
   asynchronous-only and nothing in its surface says so. Decide whether that is
   the intended scope before building a fixture that traps synchronously —
   otherwise the first test written against this will hang, correctly, and read
   as a defect in the new code.

   **UPDATE 2026-09-21 — this got smaller, and the fix is a consequence of the
   landing itself.** `mepc` is CSR `$341`, so a handler can now step the return
   address by hand: `csrr t0, $341 / addi t0, t0, 4 / csrw $341, t0`, which is
   what `test_esp_bare_csr.pas` does and why its two `ecall`s both return. So
   the capability exists; what is still missing is any *surface* for it on an
   `interrupt;` body, and the hazard is unchanged for anyone who does not know
   to write those three instructions. **The `+4` is also not universally
   right** — it assumes a 4-byte trapping instruction, and RV32C compressed
   instructions are 2 bytes — so a general answer reads the trapping
   instruction rather than assuming a width. The fixture is safe because
   `ecall` is always 4 bytes.

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

## Log
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
