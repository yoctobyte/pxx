---
slug: bug-a-no-probe-can-see-the-sweep-thunks-stack-alignment-constant
title: No probe can see the sweep thunk's stack-alignment constant — building it wrong still passes
type: bug
track: A
prio: 30
status: done
owner: frank-coord-core
---

## Summary

**RESOLVED the same day it was filed, by building the probe it describes.**
`test/test_sweep_thunk_preserves_stack_alignment.pas` now fails when either
constant is wrong: 4 against 12 on x86-64, 8 against 12 on i386. See the
resolution at the bottom, including the fact that the FIRST version of that
probe was itself blind.

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


## Resolution

Built the probe this ticket specifies, and it works: an interface local's
release is the one path in the sweep that runs USER code
(`SXR_INTF -> PXXIntfRelease -> _Release -> Destroy`), so the destructor's frame
inherits the alignment the sweep ran with, and `PtrUInt(@local) and 15` reads it
with no inline asm.

**THE FIRST VERSION OF THE PROBE WAS ITSELF BLIND, AND ONLY THE POSITIVE CONTROL
CAUGHT IT.** It compared a three-return procedure against a one-return one and
read the recorded residue after each loop. Both loops ran `1 to 30`; `30 mod 3`
is 0, which selects the three-return procedure's FIRST return — and a body's
first return is always emitted inline. So both readings came from inline sweeps,
they agreed trivially, and the test printed `ALIGN OK` against a deliberately
broken compiler **on both targets**. Sampling the final iteration meant the arm
under test was never the arm measured.

That is this ticket's own defect one level up: a guard whose expected value is
produced by the path it is not testing. It was found the same way as the
original — by running it against a build known to be wrong — which is the
argument for making the deliberately-broken build a routine step and not a
flourish.

**The fix removes the dependence on which path the last iteration took:** record
min and max of the residue over EVERY destructor call, and assert they are
equal. One three-return body already contains both arms, so the cross-procedure
control is not needed at all. No absolute expected value appears anywhere, so
there is nothing for a do-nothing default to collide with, and the row needs no
per-target constant — it is correct on any target that gets a thunk.

Controls, both directions, both targets:

| build | x86-64 | i386 |
| --- | --- | --- |
| correct constants | `ALIGN OK` | `ALIGN OK` |
| compensation wrong | `ALIGN MISMATCH lo=4 hi=12` | `ALIGN MISMATCH lo=8 hi=12` |

Wired into `test-core`, which is tier-enrolled. The five remaining targets now
each land against a guard that already exists, which was the reason for doing
this before them rather than after.
