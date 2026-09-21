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
  The xtensa half of the raw-ISR install, split out of
  feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-installed
  when its riscv32 half landed 2026-09-21. On xtensa an `interrupt;` handler
  still cannot be installed and still has no stack of its own, so BOTH halves
  of the hazard that keeps `@<interrupt proc>` refused are intact there — and
  the refusal is now narrowed to permit bare riscv32 only, which is exactly
  what makes this ticket the remaining work rather than a duplicate. Two
  things are missing and they must land together for the same reason they did
  on riscv32: a `wsr a4, vecbase` (the install, which fails today with
  `asm: unknown symbol: vecbase`), and a dedicated ISR stack in the xtensa
  `interrupt;` prologue. Landing the install alone would put a handler on the
  interrupted task's stack with no runtime stack guard, which is the loaded
  gun the riscv32 ticket talked itself out of shipping. THE MECHANISM DOES NOT
  TRANSFER AS WRITTEN: riscv32's switch uses an `mscratch` round-trip to solve
  "a trap arrives with no free register", and xtensa's equivalent is the
  EXCSAVE_n register file (one per interrupt level), not a single scratch CSR
  — so the prologue is a different shape and the level matters. Xtensa is the
  owner's primary ESP target, which is why this is 60 and not lower; it was
  sequenced second only because one unlocked path is worth more than two
  locked ones.
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

Measured at `ed1c3dfe6`: `wsr a4, vecbase` fails with
`asm: unknown symbol: vecbase`. That is the same class as riscv32's named-CSR
failure and has the same cause — an identifier in an inline-asm operand is
resolved as a SYMBOL by `asmenc.inc` before the per-arch assembler sees the
line. **So do not plan on a named `vecbase`**; the riscv32 answer was a
numeric operand, and the xtensa answer will have to be whatever `wsr`'s
special-register operand is spelled numerically.

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
