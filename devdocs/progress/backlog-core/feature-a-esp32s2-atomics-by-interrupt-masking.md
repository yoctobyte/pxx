---
slug: feature-a-esp32s2-atomics-by-interrupt-masking
track: A
tags: [S]
type: feature
prio: 25
status: open
owner: ""
created: 2026-09-24
found-by: frankH (measuring --target=esp32s2)
blocked-by: []
summary: "--target=esp32s2 REFUSES any atomic, by name, because the S2's core config has S32C1I = 0 (IDF core-isa.h), and the xtensa backend's only atomic is s32c1i. That also refuses the coroutine scheduler. The S2 is single-core, so an atomic can be done correctly by masking interrupts around a load and store (rsil / wsr.ps), the same way the esp32c3's no-A-extension arm already does it. Nothing to verify it on: there is no S2 QEMU machine and no S2 board on this bench, so land it only with a way to run it."
---

# esp32s2: atomics by interrupt masking

## The mechanism (2026-09-24)

`SocHasAtomicISA` (defs.inc) is false for SOC_ESP32S2. When an IR atomic
reaches the xtensa emitter on that chip, it refuses with a message that names
this ticket. Before 2026-09-24, `--target=esp32s2` emitted `wsr.scompare1` /
`s32c1i` pairs (six in scheduler.pas), which is an illegal instruction on S2
silicon. It built without complaint and would have crashed on the first CAS.

## What the arm needs

- Single core, so no cross-core race. `rsil aN, XCHAL_EXCM_LEVEL` saves PS and
  masks interrupts; then do the load, compare and store; then `wsr.ps aN; rsync`
  restores PS.
- A model for it already exists in the esp32c3 path (RISC-V without the A
  extension).
- Needs a run on something that executes S2 code. QEMU has no esp32s2 machine,
  so this needs an S2 board.
