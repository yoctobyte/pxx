---
slug: bug-a-xtensa-windowed-refuses-ir-raise-because-unwind-needs-the-windows-spilled
title: "xtensa windowed refuses IR_RAISE because a longjmp-style unwind needs the register windows spilled first"
track: A+S
prio: 45
type: bug
status: open
created: 2026-08-30
found-by: frankS
summary: "Under the xtensa windowed ABI, IR_RAISE and the unwind path refuse. The cause is a RUNTIME gap, not a prologue gap: a longjmp-style unwind must spill the register windows first and bare-metal has no handler for that. Filed to keep it OUT of the four-target cdecl prologue change, which would appear to fix it and would not."
---

# The gap

Under `XTENSA_ABI_WINDOWED`, `IR_RAISE` and the unwind path refuse. Call0 is fine —
`af5d2b534` gave xtensa the proc exception cleanup frame, and at HEAD
`TargetHasProcCleanupFrame` (`ir_codegen.inc:11777`) carries
`(TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_CALL0)`, with windowed
deliberately false.

**The cause is a runtime gap, not a codegen or prologue gap.** A longjmp-style unwind on
windowed xtensa must spill the register windows before it can transfer control, and
bare-metal has no handler to do that spill.

## Why this is filed rather than folded into the cdecl work

`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets` gives
i386/arm32/aarch64/riscv32 a real C-convention prologue arm. Xtensa is **explicitly out of
that ticket's scope**, and the reason is the trap rather than the tidiness (frankS):

> It would not fall out of frankA's change even if the arm were added — **it would just look
> like it had.**

That is the failure mode the whole day has been about: a change that appears to fix a target
it did not touch produces a green that means nothing. Adding xtensa as a fifth slice there
would have manufactured exactly that.

## Scope

Track S owns it, file-owned by A (`ir_codegen.inc` / `ir_codegen_xtensa.inc`) and B
(`lib/rtl/platform/esp/**`) depending on where the spill lands. **Not urgent** — Call0 is the
working configuration and windowed refusing is honest refusal, not silent wrong behaviour,
which is the deliberate ESP failure mode.

## Gate

Whatever lands must show the refusal is gone **by running a raise under windowed**, not by
observing that `TargetHasProcCleanupFrame` now returns true. And it must name the sha of the
binary the measurement came from.
