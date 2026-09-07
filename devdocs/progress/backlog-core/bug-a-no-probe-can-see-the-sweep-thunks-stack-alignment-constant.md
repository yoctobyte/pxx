---
slug: bug-a-no-probe-can-see-the-sweep-thunks-stack-alignment-constant
title: No probe can see the sweep thunk's stack-alignment constant — building it wrong still passes
type: bug
track: A
prio: 30
status: open
owner: frank-coord-core
---

## Summary

The managed-local sweep thunk (`EmitSweepThunkStackAdjust`, ir_codegen.inc)
compensates for the return address a `call` pushes, so the sweep's own calls see
the stack alignment the INLINE sweep saw: `sub rsp,8` on x86-64, `sub esp,12` on
i386. **Emitting the wrong constant changes nothing any test can observe.**

Measured 2026-09-07, by building it wrong on purpose: with the x86-64 value (8)
emitted on i386 — misaligning every call the sweep makes by 8 —
`test_managed_sweep_thunk` ran natively on i386 and printed
`SWEEPTHUNK OK ok=80000 caught=5000` with census `allocs=40103 frees=40101
live=2`, identical to the correct build in every digit, exceptions included.

So the constant is correct by the SysV contract that `symtab.inc:12870` and
`ir_codegen386.inc:3723` both state, and it is **not** correct by measurement.
It is a value with no guard behind it.

## Why the corpus cannot reach it

Three independent reasons, all of which would have to change:

- The sweep's callees are pxx-internal release stubs.
- Neither backend emits a memory-operand `movaps`/`movapd`/`movdqa`. The x86-64
  hits are all register-to-register (`movaps xmm0, xmm8`), which has no
  alignment requirement.
- The external-call path re-aligns for itself (`and esp,-16`,
  ir_codegen386.inc:3815) rather than trusting the alignment it was handed.

## What would see it, and why this is not hypothetical

A released **interface** whose `_Release` runs user code that calls an external
function using aligned SSE. `symtab.inc:16362` records precisely that fault mode
already: *"callees (GTK/GLib) use aligned SSE (movaps) and fault otherwise."*
That path exists today; the leak corpus simply does not walk it.

Proposed probe, cheapest form first, and **it needs no inline asm**: give a
refcounted interface implementation a `Destroy` that takes the address of a
local and records `PtrUInt(@local) mod 16` into a global. A stack local's
address carries the frame's alignment. Hold that interface in a procedure with
three-plus managed locals and two-plus returns so the thunk fires, then compare
the recorded residue between a thunked and a non-thunked build. They must agree;
with a wrong constant they differ by exactly the miscompensation. That is a
differential probe, so it needs no absolute expected value and cannot collide
with a do-nothing default — the failure mode CLAUDE.md warns about for any row
whose expected value is a small power of two.

## Why the adjustment stays rather than being dropped as inert

Because "the thunk body sees the stack the inline sweep saw" is a cheaper
invariant to hold than auditing every transitive callee, forever, against a
requirement that already has a recorded fault mode in this tree. It costs 6
bytes once per thunk against a measured -31.9%.

## Scope

Both arms landed unverified in this respect. x86-64 at `50e25f5f0`, i386 in the
commit that files this. The five remaining targets will each add a constant of
their own with the same blind spot unless this probe exists first — **which is
the argument for doing it before them, not after.**
