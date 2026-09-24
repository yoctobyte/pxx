---
slug: feature-a-port-alloca-to-xtensa
track: A
prio: 30
type: feature
blocked-by: []
summary: "DONE 2026-09-24 (frankH). IR_ALLOCA has an xtensa arm for both ABIs. CALL0 moves sp per push, so it is riscv32's arm (a base word holding where the expression stack starts, then relocate and return the gap). WINDOWED keeps sp constant, so: MOVSP down (the alloca exception handles the caller's a0-a3 block), copy the live [sp, sp+XtSpillDepth) words, and place the block above the WHOLE reserved spill region at new sp + XtSpillMax. That offset is a literal PatchProcPrologue fills in, and 16 bytes of slack pay for aligning the block. Verified: 00207 plus c_alloca_expression_stack / c_alloca_in_call_argument / c_vla / test_alloca PASS on tools/run_c_conformance_esp.sh --chip esp32s3 (qemu, windowed). Two of them are byte-exact on an ESP32-S3 board. All four match x86-64 hosted on call0, with new test-xtensa rows."
status: done
---

# Port IR_ALLOCA to xtensa

Found 2026-09-24 (frankS) by the esp32s3 leg of tools/run_c_conformance_esp.sh:
00207.c (a VLA) is `unsupported node in IR codegen: alloca`.

## Measured

- 00207.c passes byte-exact at HEAD on riscv32, arm32, i386 and aarch64
  (qemu-user) and on esp32c3 under IDF; the desktop skip lines claiming
  "alloca is x86-64 only" were stale and were removed the same day.
- xtensa refuses at codegen, both ABIs.

## Why it was not done with the finding

The windowed backend's constant-sp model (see `XtSpillDepth`,
`XtensaLoadArgRegsWindowed`, `XTENSA_WIN_*` reserves in defs.inc) means an
alloca is not "sub sp; relocate": every sp-relative slot the body has already
computed an offset for moves with it, and the base save area below sp must
move too (movsp). That wants a design pass, not a same-session port.

## Condition that retires this

00207.c PASS on `tools/run_c_conformance_esp.sh --chip esp32s3`, and a hosted
call0 row against x86-64 in test-xtensa.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 60c34618a.
