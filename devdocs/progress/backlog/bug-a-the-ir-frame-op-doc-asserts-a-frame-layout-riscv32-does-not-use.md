---
track: A
prio: 25
type: bug
blocked-by: []
summary: "defs.inc:816 documents IR_FRAME with 'the saved-fp chain IS walkable: [fp] = the caller's fp, [fp + PtrSize] = the return address' — stated as universal. It is false on riscv32, where s0 points at the BOTTOM of the frame and the links sit at +8/+12. ir.inc:4977 knows this and says assuming the common layout 'would have silently walked into the locals'. The lowering is correct (it asks FramePrevFpOffset/FrameRetAddrOffset); the DOC a backend implementer reads is not."
---

# `IR_FRAME`'s documentation asserts a frame layout riscv32 does not use

- **Track A** — `compiler/defs.inc:816`. Comment only; **no live bug**.
- Found by the sweep for
  [[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]].

## The two artefacts

`defs.inc:816`, documenting `IR_FRAME`, states the property as universal:

> Every pxx prologue pushes a real frame pointer and links it, so the saved-fp
> chain IS walkable: **[fp] = the caller's fp, [fp + PtrSize] = the return
> address into the caller.** get_pc_addr and get_caller_stackinfo are built from
> this op plus ordinary loads, so this is the ONLY op the backends need.

`ir.inc:4977`, above `FramePrevFpOffset` / `FrameRetAddrOffset`, states the
opposite for one arm:

> riscv32 is the odd one: s0 is left pointing at the BOTTOM of the frame, not
> above the saved pair, so its links are at **+8/+12** rather than +0/+PtrSize.
> **Assuming the common layout here would have silently walked into the locals.**

## Why this is worth a ticket even though nothing is broken

The lowering is **correct**: `ir.inc:7607/7631/7639` build the walk from
`FrameRetAddrOffset` / `FramePrevFpOffset` rather than from `PtrSize`, and
`ir_codegen_riscv32.inc:1264` carries a pointer to them. Checked; no defect in
emitted code.

The defect is that `defs.inc` is the **IR-op reference** — the file a person
adding a target or a frame intrinsic reads to learn what `IR_FRAME` guarantees —
and it states a false universal with no exception and no pointer to the two
accessors. The sentence *"this is the ONLY op the backends need"* actively
discourages looking further. A new target with a riscv32-shaped prologue, or a
new intrinsic built "from this op plus ordinary loads" as the doc invites, walks
into the locals exactly as `ir.inc` warns — silently, which is the failure mode
that comment exists to prevent.

## Fix

One clause in `defs.inc:816`: the chain is walkable, **but the offsets are
per-target — ask `FramePrevFpOffset` / `FrameRetAddrOffset` (ir.inc), never
assume +0/+PtrSize; riscv32 is +8/+12.** Do not restate the layout table; there
is already exactly one place it is written down and the point is to route
readers to it.

## Gate

Comment-only. `make compiler/pascal26` (the fixedpoint) and nothing else.
