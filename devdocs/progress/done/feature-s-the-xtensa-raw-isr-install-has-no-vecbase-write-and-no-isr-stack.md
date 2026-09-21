---
slug: feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-stack
track: S
type: feature
prio: 60
status: done
owner: frankb-8e
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: >
  LANDED 2026-09-22. Bare xtensa can now install a raw vector table and enter
  an `interrupt;` handler that runs on a dedicated ISR stack;
  test/test_esp_bare_vector.pas boots under qemu on esp32s3 byte-identical to
  the x86-64 oracle. Four things had to land together and three of them were
  defects nobody had seen, because the xtensa `interrupt;` codegen was
  COMPLETE AND UNREACHABLE -- prologue, epilogue and `rfe` all written, and no
  way to install a vector, so none of it had ever executed on any instrument.
  (1) THE VECTOR STUB IS A SINGLE `j`, which is what makes the rest cheap: an
  18-bit PC-relative jump reaches +/-128 KiB with no register operand, so the
  table hands the handler an untouched machine and EXCSAVE_1 is free for the
  prologue's stack switch. VECBASE at 1 KiB alignment is measured, not assumed.
  SECOND LANDING, SAME DAY: THE COMPILER NOW EMITS THE TABLE, so a program
  declares a routine `interrupt;` and takes a trap -- no BSS window, no
  displacement arithmetic, no `@MyIsr`, no inline asm
  (test/test_esp_bare_vectorauto.pas). The install is a DEFAULT and not a
  lock: it runs at the top of the main body, so a program that writes VECBASE
  itself still wins, and test_esp_bare_vector.pas is what keeps that path
  alive. Two things that made it non-obvious. The table is emitted AFTER
  DceRun, because DCE is default-on for bare ESP and compacts code after
  parsing -- a parse-time table had its padding and its `j` computed against
  addresses that no longer existed, silently (tableAt=73612 against a final
  code=8360B); the halves join through a DATA word, which DCE does not move.
  And `interrupt;` had to BECOME a DCE root (DCE_WHY_VECTOR): it had never
  needed to be, because installing a handler used to require `@MyIsr`, so
  every such body was reachable as DCE_WHY_PROCADDR and the gap was masked by
  the very awkwardness the table removes.
  (2) PS WAS NEVER INITIALISED BY ANY BARE IMAGE. At reset PS.EXCM is SET
  (measured: PS = $1F), and EXCM=1 makes every exception a DOUBLE exception --
  routed to VECBASE+0x3C0, PC in DEPC not EPC1, returned from with RFDE not
  RFE. The epilogue emits RFE and reads EPC1, so the whole path was returning
  from the wrong KIND of exception with the wrong register: EPC1 read back as
  0 and the RFE jumped to address 0. The entry stub now writes PS = $2F
  (INTLEVEL 15 unchanged, EXCM cleared, UM 1) plus RSYNC.
  (3) A CALL OUT OF AN `interrupt;` HANDLER JUMPED TO ADDRESS 0, ON BOTH BARE
  ISAs. `interrupt;` implies `iram;` (pasparser_proc.inc), so any call to an
  ordinary proc took the cross-section indirect path, whose literal is patched
  ONLY by the ET_REL object writer. A bare build is ET_EXEC with one PT_LOAD
  and no linker, so the literal stayed zero. Guarded with `not EspBareBoot`:
  on bare there is no flash/IRAM split to span and the direct PC-relative call
  is always in range. CONTROL: with the guard reverted, both the esp32c3 and
  esp32s3 fixtures produce no output at all.
  THE REFUSAL IN ir.inc IS NARROWED, NOT DELETED, and on the axis it argues
  from -- the hazard it names is "no ISR stack", and the xtensa prologue now
  switches to one (EXCSAVE_1 where riscv32 uses mscratch). ESP-IDF keeps
  refusing on both ISAs because that arm is also the
  `interrupt;`-instead-of-`iram;` esp_intr_alloc mistake.
  TWO xtensa/riscv32 DIFFERENCES THAT BIT: the ENCODER takes (sr, at) while
  the text syntax is (at, sr), and written the text way round it still
  assembles -- sr := 2 is LCOUNT and at := $D1 masks to a1, so the prologue
  silently began `wsr.lcount a1` with no diagnostic; and l32i/s32i offsets are
  UNSIGNED 0..1020, so riscv32's `sw sp,-4(t0)` does not transfer (caught as a
  build error by XtensaCheckWordOffset, which is the good case).
  No pin needed to USE any of this -- it is compiler codegen, and the fixtures
  build with the freshly built compiler. A pin is needed before any lib/**
  code can depend on it.


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

## Resolution 2026-09-22 (frankb-8e)

Landed. `test/test_esp_bare_vector.pas`, wired into the bare tier, boots on
esp32s3 under the Espressif qemu byte-identical to the x86-64 oracle.

### What the fixture asserts, and none of it is "the handler ran"

    j in range 1                        the stub's 18-bit reach, range-checked
    handler ran 1
    exccause 1                          SyscallCause, via the User vector
    a call from the handler returned    the iram-crossing bug (3)
    isr sp is ABOVE task sp             the dedicated ISR stack
    locals survived the trap            the epilogue restored the frame
    VECTOR-OK

**Positive control, run:** disabling the ISR-stack switch in BOTH the prologue
and the epilogue leaves `handler ran 1`, `exccause 1`, the call row and the
locals row **all GREEN** and reddens only the stack row. That is the shape the
riscv32 ticket prescribed — assert the stack, not the entry — and it is the
reason "it ran" is not the assertion anywhere in this fixture.

**Only the User vector (0x340) is planted.** Not 0x300, not 0x3C0. A spare slot
would absorb a regression in the PS init, and — measured the hard way — a table
with a catch-all converts a fault *inside* the handler into a re-entry that
reads as the feature working. Written up in the playbook, "A CATCH-ALL ENTRY IN
A DISPATCH TABLE TURNS EVERY FAULT INTO A SUCCESSFUL-LOOKING LOOP".

### The riscv32 sibling got the same row

`test/test_esp_bare_isrstack.pas` now calls an ordinary proc from its handler.
It never had, which is why defect (3) was invisible on that ISA too. With the
`not EspBareBoot` guard reverted, esp32c3 produces no output at all.

### What is NOT done

- **Nothing emits the vector table.** The fixture builds it at runtime out of a
  BSS array. That is honest for a test and is not an API: a program wanting a
  raw vector today writes the same twenty lines. Whether the compiler should
  emit an aligned table, and how a handler would be bound to a slot, is a
  design question and deliberately not settled here.
- **Level 1 only.** The prologue spends EXCSAVE_1 and the epilogue returns via
  `rfe`; both are level-1 facts. A higher-level handler needs RFI and EXCSAVE_n
  and is a different prologue, not a parameter of this one.
- **Nesting.** Unneeded at level 1 — PS.EXCM masks further level-1 exceptions
  until RFE clears it, the xtensa counterpart of RISC-V clearing mstatus.MIE.
  One ISR region is correct on both ISAs for that reason.

## Resolution, second landing 2026-09-22 (frankb-8e) — the compiler emits the table

The first landing made a raw vector table WORK. It did not make it usable: the
fixture that proved it contains a BSS window, an alignment computation, a
hand-assembled 18-bit displacement and a `wsr vecbase` in inline asm — roughly
twenty lines that no Pascal program should have to carry, for a capability the
owner names as a must-have.

**What a program writes now**, in full:

```pascal
procedure MyIsr; interrupt;
begin
  ...
end;
```

No table, no VECBASE, no `@MyIsr`. Declaring it is the install.

**Where it lives.** `EmitBareVectorInstallForTarget` (ir_codegen.inc) runs at
parse time from `pasparser_prog.inc`, right after the program entry jump is
patched: it allocates a zeroed data word and emits `l32i` / `wsr vecbase` /
`rsync` against it. `EmitBareVectorTableAfterDce` runs from `compiler.pas`
immediately after `DceRun`: it pads to 1 KiB, records `BareVecTableAt`, plants
a single `j` to the handler at the User offset 0x340 and zero-fills to 0x400.
`elfwriter.inc` patches the data word with `entry + BareVecTableAt`.

**Why split across DceRun** is the finding worth keeping, and it is in the
playbook as "MAKING A REFERENCE IMPLICIT MAKES THE THING IT REFERENCED
GARBAGE — AND DCE RUNS AFTER YOU EMITTED". Short form: DCE is default-on for
bare ESP and compacts code after parsing, so the first implementation's
padding and `j` were computed against addresses that no longer existed — no
diagnostic, no output, `tableAt=73612` against a final `code=8360B`. Data does
not move under DCE, which is why the halves are joined through a word and not
an offset.

**Only the User vector is planted.** The other 255 slots stay zero,
deliberately: a fault inside the handler must land on a hole and stop, not be
absorbed. The first landing lost three rounds to a probe that filled every
slot, which converted "this handler faults" into "this handler runs
repeatedly" — playbook, "A CATCH-ALL ENTRY IN A DISPATCH TABLE TURNS EVERY
FAULT INTO A SUCCESSFUL-LOOKING LOOP".

**EPC1 is still the handler's to step**, and that is a decision rather than an
omission. `syscall` leaves EPC1 addressing the syscall, so a handler that
returns without advancing it re-executes forever — but the right step is 3 for
a syscall and 0 for an asynchronous interrupt that must resume where it was
preempted. A compiler that guessed would be wrong for one of the two and
silent about it.

### Controls, all four run

| control | expected | observed |
| --- | --- | --- |
| two `interrupt;` procs | refuse, name both | `error: two routines are declared 'interrupt;' (A1 and B1) ... the hardware has ONE level-1 vector` |
| one `interrupt;` proc, same shape | compile | ok, `code=2956B` |
| same source without the keyword | no table | `code=916B` — the 1 KiB table and its padding are the delta |
| alignment assert (padding disabled) | refuse | `error: internal: the bare exception vector table landed at 0x40378494, which is not 1024-byte aligned` |
| DCE root reverted | auto fixture dies, manual one lives | auto: builds, boots, prints nothing; manual (`@MyIsr`) fully green |

The DCE control is the load-bearing one and it is asymmetric on purpose — a
shared failure would have meant something else was wrong.

**Structural check on the emitted image** (`one_isr.elf`, entry 0x40378074):
table at VMA 0x40378800, i.e. 1 KiB-aligned; `06 04 fe` — a `j` — at file
offset 0xb40 = table + 0x340; and 0x40378800 present as the patched data word.

**Fixtures.** `test/test_esp_bare_vectorauto.pas` is new and wired into the
bare tier. `test_esp_bare_vector.pas` STAYS: it is now the regression test for
the override, since the compiler's install is a default and a program must
still be able to point VECBASE somewhere else. Both are green on esp32s3,
byte-identical to their x86-64 oracles, as are `test_esp_bare_isrstack.pas`
and (cross-ISA, untouched) `test_esp_bare_csr.pas` on esp32c3.

**Still bare-xtensa only.** riscv32 has `mtvec` and its own install path; this
table is the xtensa answer and `EmitBareVectorTableAfterDce` exits immediately
on any other target or profile.
