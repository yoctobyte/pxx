---
slug: feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-stack
track: S
type: feature
prio: 60
status: backlog
owner: ""
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: >
  PARTIALLY LANDED 2026-09-21: `wsr`/`rsr` WITH A NUMERIC SPECIAL REGISTER NOW
  WORK, so VECBASE ($E7) and the EXCSAVE_n scratch file ($D1..$D7) are
  reachable from Pascal for the first time; test_esp_bare_sr.pas round-trips
  EXCSAVE_1 under qemu on esp32s3, byte-identical to the x86-64 oracle, and
  the pinned compiler cannot build it. All eight encodings were diffed
  byte-for-byte against xtensa-esp32s3-elf-as, and the four previously
  hardwired helpers (scompare1 x2, atomctl, cpenable, prid) are now DERIVED
  from the general form rather than restating it -- controlled behaviourally
  by running the xtensa atomics under qemu with the pinned AND HEAD
  compilers, since that codegen is what calls them.
  THE INSTALL IS STILL NOT POSSIBLE, AND THE REASON IS THE FINDING: VECBASE
  POINTS AT A VECTOR **TABLE**, NOT AT A HANDLER. Measured from ESP-IDF's own
  linker script (components/esp_system/ld/esp32s3/sections.ld.in), each vector
  sits at a fixed offset from the base -- 0x180 Level2, 0x1c0 Level3, 0x200
  Level4, 0x240 Level5, 0x280 Debug, 0x2c0 NMI, 0x300 KernelException, 0x340
  UserException, 0x3C0 DoubleException, 0x400 end. And a level-1 interrupt
  does not even get its own slot: it arrives at the USER exception vector with
  EXCCAUSE = 4 and must be dispatched there. So the xtensa install is NOT the
  one-register write riscv32's mtvec was, and anyone planning it from the
  riscv32 experience will plan the wrong job: it needs an aligned table
  emitted into IRAM with stub code at the right offset, which is compiler work
  and a placement decision, not an instruction.
  STILL MISSING, both halves: that vector table, and a dedicated ISR stack in
  the xtensa `interrupt;` prologue. They must land together for the reason the
  riscv32 ticket established -- an install without a stack is a handler on the
  interrupted task's stack with no runtime guard. The `ir.inc` @<interrupt
  proc> refusal is currently narrowed to bare riscv32 ONLY and must be
  narrowed further, never deleted, when this lands; the ESP-IDF arm keeps
  refusing on both ISAs because it is also the `interrupt;`-instead-of-`iram;`
  esp_intr_alloc mistake.
  TWO THINGS NOT TO CARRY OVER FROM riscv32. The scratch mechanism differs:
  EXCSAVE_n is one register PER INTERRUPT LEVEL, so the prologue must know its
  level, where riscv32 machine mode has exactly one mscratch and could be
  level-agnostic. And the OPERAND ORDER is register-first -- `wsr a4, $e7`,
  verified against the GNU assembler, which ACCEPTS `wsr a4, 231` and REJECTS
  `wsr 231, a4`; that is why these needed no reordering around the generic
  operand parse, unlike riscv32's csrw whose CSR genuinely is operand one. An
  earlier probe of mine used the reversed order and read its (correct)
  "expected register" refusal as the same operand-class gap riscv32 had. It is
  not one.
---

# The xtensa raw-ISR install has no vecbase write and no ISR stack

## Why this is a separate ticket rather than the same one

Its riscv32 sibling delivered three things that are only useful together: CSR
access, an ISR stack, and a narrowing of the `ir.inc` `@<interrupt proc>`
refusal onto the target where the stack now exists. All three were measured
and are green under qemu.

**None of the three transfers.** The install instruction is different
(`wsr vecbase`, not `csrw mtvec`), the scratch mechanism is different
(EXCSAVE_n per level, not one `mscratch`), and the refusal is currently
narrowed *against* xtensa on purpose — measured 2026-09-21, xtensa bare still
answers `cannot take the address of MyIsr`.

## What is measured, and what is not

**`wsr`/`rsr` with a numeric SR landed 2026-09-21 and this section's original
"what is missing" is half retired.** `wsr a4, $e7` assembles;
`test/test_esp_bare_sr.pas` round-trips EXCSAVE_1 on esp32s3 under qemu.

A named `vecbase` still does not work and never will from inline asm:
`wsr a4, vecbase` fails with `asm: unknown symbol: vecbase`, because an
identifier in an asm operand is resolved as a SYMBOL by `asmenc.inc` before
the per-arch assembler sees the line. Write the number.

**THE INSTALL IS THE PART THAT DID NOT GET SMALLER, AND MEASURING IT IS WHAT
CHANGED THE SHAPE OF THIS TICKET.** From ESP-IDF's own linker script
(`components/esp_system/ld/esp32s3/sections.ld.in`), VECBASE is the base of a
**table**:

    0x000 WindowVectors   0x180 Level2   0x1c0 Level3   0x200 Level4
    0x240 Level5          0x280 Debug    0x2c0 NMI      0x300 KernelException
    0x340 UserException   0x3C0 DoubleException         0x400 end

So `wsr a4, $e7` is not an install — it relocates a table that a bare PXX
image does not have. A raw install needs that table emitted into IRAM at an
aligned address with stub code at the right offset. **And a level-1 interrupt
has no slot of its own**: it arrives at the USER exception vector with
`EXCCAUSE = 4` and has to be dispatched there.

**This is the thing to carry away, because it is not visible from the riscv32
side**: `mtvec` is a handler address and `vecbase` is a table base. A plan
written by analogy will size the job as one instruction and it is not.

## Is the stack carve FORCED here, as it was on riscv32? — measured, yes

Asked because the two are different claims and only one had been checked: *"the
riscv32 discriminator should transfer"* (the `handler sp > task sp` comparison)
and *"the constraint that produced it transfers"* (that the carve was not a
choice). The first was recorded as available-not-verified. **The second is now
measured and the answer is yes.**

`ir_codegen.inc`'s xtensa bare arm does
`EmitLoadConstXtensa(reg_xtensa_sp, ESP_BARE_STACK_TOP)` — a compile-time
constant, in the same entry stub, emitted before the body is parsed. So on
xtensa too the stack top must be fixed while *"does this program contain an
`interrupt;` body"* is still undecided, and a conditional ISR region would need
the same entry-stub patch the riscv32 ticket declined to build. **The carve is
forced on both ISAs for the same structural reason**, and it is not a fresh
decision on xtensa.

Two things that did NOT transfer and are worth knowing before writing the
prologue:

- `EmitLoadConstXtensa` drops a **literal island** rather than emitting a
  `lui`/`addi` pair, so the constant lives in a pool. That changes what a
  future patch-the-entry-stub refinement would have to patch, in xtensa's
  favour — a pool slot is a word, not a split immediate.
- **The xtensa entry parks every core but core 0** (`rsr.prid`, `$CDCD`, spin)
  because under `qemu -kernel` both S3 cores execute the entry. Only core 0
  reaches the stack setup, so a single ISR stack is not a dual-core hazard
  *today* — but that is a property of the park, not of the design, and anyone
  who removes the park inherits the question.

## What else is measured, and what is not

**NOT measured, and it is the first thing to establish:** whether xtensa's
`interrupt;` prologue has any equivalent hazard boundary to assert against.
riscv32's fixture works because the ISR stack is carved from the top of the
SRAM stack region, so `handler sp > task sp` is a comparison that a broken
build cannot land on the passing side of. Check that the same arrangement is
available on the S3 memory map before writing the fixture, rather than
assuming it.

## The shape to copy, and the one thing not to copy

Copy: **assert the STACK, not the entry.** riscv32's control was to disable
both switch sites and re-run — `isr hits 2` stayed green while the stack row
reddened. "The handler ran" is true with and without the fix and therefore
cannot be the assertion.

Do not copy: the `mscratch` round-trip. Xtensa Call0 has `EXCSAVE_1..7`, one
per interrupt level, which is a better fit than a single scratch register but
means the prologue must know its level. The riscv32 prologue could be
level-agnostic because RISC-V machine mode has exactly one.

## Related

- `feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-installed`
  (done/) — the riscv32 half, with the worked mechanism.
- `compiler/ir.inc` — the `@<interrupt proc>` refusal, narrowed to bare
  riscv32. **Narrow it further when this lands; never delete it.** The
  ESP-IDF arm must keep refusing on both ISAs, because that is also the
  `interrupt;`-instead-of-`iram;` esp_intr_alloc mistake.
- `test/test_esp_bare_isrstack.pas` — the riscv32 fixture to mirror.
