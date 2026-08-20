---
track: A
prio: 45
type: bug
blocked-by: []
summary: "test_dynarray_named_alias_element passes 26/26 natively and CRASHES on arm32 and aarch64 (SIGSEGV) and produces no output on riscv32. The Track P fix that made `array of <named dyn-array alias>` compile at all (907f18d9e) landed the frontend half; the four cross backends never handled the shape. Pre-existing — riscv32 fails with zero cross-target changes applied."
status: backlog
owner: unassigned
---

# `array of <named dyn-array alias>` crashes on every cross target

- **Track A** (cross-target codegen: `ir_codegen386.inc`,
  `ir_codegen_arm32.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_riscv32.inc`).
- Found 2026-08-21 during a cross-target sweep of the dyn-array tests.

## Measured

`test/test_dynarray_named_alias_element.pas`, current HEAD:

| target | result |
| --- | --- |
| x86-64 | **total ok 26 / 26** |
| arm32 | SIGSEGV |
| aarch64 | SIGSEGV |
| riscv32 | no output at all |

The test did not exist as a *compilable* program before
`907f18d9e fix(P): array of <named dyn-array alias> in a TYPE decl kept its
dimension` — a compiler older than that rejects it with an overload-resolution
error (`argument types: (ShortString, Integer, ShortString)`), because the
element type came out wrong. So the frontend half landed and the cross backends
were never taught the shape.

## Not a regression from the interface-container work

Checked deliberately rather than assumed, because that work was in flight when
this surfaced: **riscv32 fails with zero of those changes applied to it.** Its
epilogue, its store path and its element-kind handling are all untouched in the
tree that produces the failure above. The same reasoning clears arm32, whose
only change was *removing* a call (an accidental `PXXStrDecRef` on an array's
data pointer) — dropping a release cannot produce a segfault.

## Where to start

`Syms[].ElemType` / `SymElemDynDepth` for the aliased element is what 907f18d9e
corrected; the cross backends compute element stride and slot width from those
same fields in several places each. Dump the IR natively and on aarch64 for the
failing case and compare the stride the two backends derive — the native answer
is known-correct here, which makes this a differential rather than an
investigation.

## Gate

26/26 under `tools/run_target.sh` for i386 / arm32 / aarch64 / riscv32; native
unchanged; self-host fixedpoint + `tools/gate.sh quick`.
