---
slug: refactor-a-wasm32-is-the-one-target-the-shared-scope-exit-sweep-cannot-be-ported-to-as-a-port
title: "wasm32 and the shared scope-exit sweep — the one target where this is not a port"
track: A
prio: 25
type: refactor
status: backlog
owner: ""
found: 2026-09-07
found-by: frank-coord-core
blocked-by: []
summary: "The scope-exit managed-local sweep is now emitted ONCE per body and CALLed, on all six targets that write into a flat Code[]: x86-64 50e25f5f0, i386 3d7cde305, arm32 4a1a80184, aarch64 5f89103c9, riscv32 b1554c59a, xtensa (Call0) dde109a7a. wasm32 is the seventh target and is deliberately NOT in that sequence, so this ticket exists to stop it reading as unfinished work. wasm32 has structured control flow and no raw code addresses: WasmEmitManagedLocals writes into the epilogue, the backend writes no Code[] at all, and EmitProcEpilog is never called for it -- EmitManagedLocalCleanupForTarget's first statement is `if TargetArch = TARGET_WASM32 then Exit`. There is nothing to place at an address and nothing to CALL. A shared sweep there would have to be a REAL wasm function taking the frame as an argument, and the locals are wasm locals rather than frame slots at an offset from a base pointer, so there is nothing to pass -- a different change with a different correctness argument, not the same one with different encodings. MEASURED, not read: the byte-identity A/B for every one of the six landings shows `--target=wasm32 identical=30 differs=0`, i.e. wasm32's codegen has not moved by one byte through the whole sequence, which is the intended outcome. VALUE IS UNKNOWN AND SHOULD BE MEASURED BEFORE ANY WORK: the win on the flat-code targets is code size (compiler.pas 30.4% smaller on riscv32, 46.2% on xtensa under --xtensa-long-calls), and a wasm module's size behaves differently enough that the payoff is not inherited from those numbers. Prio 25 because nothing is broken -- the inline sweep on wasm32 is correct today."
---

# wasm32 and the shared scope-exit sweep

- **Type:** refactor — Track A
- **Found:** 2026-09-07, closing the six-backend sweep-thunk sequence

## Why this is a ticket rather than a seventh commit

The other six targets all had the same shape of answer: place the sweep once
after the body, jump over it, CALL it from every return past the first, and
spell three per-target things (a stack adjust, a call, a return). Every one of
them writes into a flat `Code[]` and can name an address inside the body being
emitted.

wasm32 cannot do any of that.

- `EmitManagedLocalCleanupForTarget` begins with `if TargetArch = TARGET_WASM32
  then Exit` — the sweep this sequence shares is not the code wasm32 runs.
- `WasmEmitManagedLocals` writes into the epilogue instead, and
  `EmitProcEpilog` is never called for this target at all.
- Structured control flow means there is no raw code address to jump over or
  call.

So the equivalent change is: emit a real wasm function that performs the sweep,
and call it. That function needs the frame — and there is no frame. The locals
are wasm locals, not slots at an offset from a base pointer, so the argument the
shared sweep would need does not exist in a form that can be passed.

## What is already established

- Every landing in the sequence carried a byte-identity A/B against the previous
  compiler across the seven targets. `--target=wasm32` reported `identical=30
  differs=0` on all six. wasm32's output has not changed by one byte, which is
  the intended outcome and is the evidence that the six arms are correctly
  scoped.
- `TargetHasSweepThunk` does not admit it, and the fall-through arms of
  `EmitSweepThunkStackAdjust` / `EmitSweepThunkCall` / `EmitSweepThunkReturn`
  each `Error(...)` with a named reason rather than silently emitting some other
  target's bytes — so admitting wasm32 by accident is a compile error, not a
  wrong binary.

## Before doing any of it, measure the value

The payoff on the flat-code targets is code size: `compiler.pas` for riscv32
went 23,179,116 -> 16,133,996 bytes (30.4%), and for xtensa Call0 under
`--xtensa-long-calls` 26,308,460 -> 14,163,820 (46.2%, inflated by that flag
making every call site large). Neither number transfers. A wasm module's size is
dominated by different things, and a function call in wasm is not the same
trade as a `call rel32`. Measure the duplicated-sweep bytes in a real module
first; if the answer is small, the right resolution of this ticket is
`rejected/` with the measurement attached.
