---
prio: 55
track: A
status: done
owner: frank-optimize
---

# -O3 (aarch64): fold a resident compare LEFT across a complex right, and drop the staging entirely

Split out of `feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen`
while landing the W1 slice 5+7 port. Filed rather than bundled because it is a
different SHAPE of change with its own control pair, not one more condition on
the arm that just landed.

- **Type:** feature (codegen — optimization) — **Track O**, file-ownership
  **Track A** (`compiler/ir_codegen_aarch64.inc`). Gate: `make compiler/pascal26`
  plus an `-O0`/`-O3` control pair run on **both** targets, aarch64 under qemu.
- **Worth:** −3 instructions per firing, including a stack round trip.

## What landed, and where it stopped

W1 slices 5+7 on aarch64 fold a register-resident compare operand — either side
— into `cmp Xn, Xm`, but only in the **const-right** and **leaf-sym-right** arms.
The general arm, where the right operand is an arbitrary subtree, still emits:

```
  mov x0, x19            <- the left, staged
  str x0, [sp, #-16]!
  <right subtree>        -> x0
  mov x1, x0
  ldr x0, [sp], #16      <- restored, only to be read once
  cmp x0, x1
```

Every one of the first five instructions exists to preserve a value that lives
in a callee-saved register the whole time. The fold reduces it to:

```
  <right subtree>        -> x0
  mov x1, x0
  cmp x19, x1
```

## Why it is safe, which is the part that was measured rather than reasoned

Two candidate hazards, both eliminated by measurement while writing the parent
slice:

1. **"The pushed x0 is garbage."** True and harmless — the cmp reads the home
   register, so the pushed value is dead. Removing the parent slice's scope
   guard on purpose left every test **green**, which is what prompted measuring
   instead of asserting.
2. **Reordering: `a < f()` where f writes `a`.** This *would* be real — reading
   the register at cmp time would see the NEW value — except that a local
   reachable through a nested procedure or a `var` parameter is marked
   **`escapes`** by the residency assigner and is never given a register.
   Verified both ways with `PXXDBG=a.resid`: the mutating probe's `a` shows
   `escapes` and no `ASSIGN` line, on both routes.

So the fold is correct in this arm too. It was excluded from the parent slice
only because doing it *there* while keeping the `str`/`ldr` saves one
instruction and leaves two dead ones — a worse change than either doing it
properly or not at all.

## Gate

`-O3`-gated. Its own `-O0`/`-O3` control pair with **band** rows, run on both
x86-64 and aarch64 (x86-64 is a third control here: it must not move at all).
`test/test_cmp_both_in_place.pas`'s `cplx` rows are the shape to extend —
`Mix(b, a)` is a complex right operand against a resident left — but note that
those rows **do not currently price the guard**, which is exactly the finding
above. A row that would: a comparison whose right subtree is complex AND whose
left is resident, with the band arranged so a reordered read differs by one.

Verify non-vacuity by breaking the encoding on purpose and confirming the
**emitted bytes** change (umbrella standing rule 4).

## Links

- Parent: `feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen`
- Umbrella: `feature-opt-o3-register-pressure` (W1)

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
