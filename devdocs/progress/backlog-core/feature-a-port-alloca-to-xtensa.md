---
slug: feature-a-port-alloca-to-xtensa
track: A
prio: 30
type: feature
blocked-by: []
summary: "IR_ALLOCA (C VLAs, alloca()) has no xtensa arm: `target xtensa: unsupported node in IR codegen: alloca`. It is the one c-testsuite row (00207.c) that red on esp32s3 for a missing feature rather than a bug. The other five backends have it; riscv32's is the model (a frame word holding where the expression stack starts, sp lowered by the 16-rounded size, the region between relocated down). xtensa is harder on the WINDOWED ABI, which IDF runs: that backend keeps sp CONSTANT and addresses its expression-stack spill slots and outgoing-argument area at fixed sp offsets, and moving sp there has to go through movsp and carry the 16-byte base save area the window-overflow handlers read below sp. Call0 is the easier half."
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
