---
slug: bug-a-hand-written-literal-short-jumps-span-emitters-that-can-grow
title: "Hand-written literal short jumps span emitters that can grow, and land mid-sequence when they do"
track: A
prio: 45
type: bug
status: backlog
created: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "About 25 short jumps in the backends carry a hand-counted literal displacement over a span emitted by other code. When that span grows the jump stays IN RANGE and lands mid-sequence, so nothing errors: measured once for real in the i386 --threadsafe I/O unlock stub, where `jne +8` grew into a push/anchor/pop wrapper, landed on the `pop`, and the nested path popped the caller's return address into eax and stored through it (fixed at cd4af7824 by converting to PatchRel8). CheckRel8 covers the 172 computed sites and hard-errors, so the OVERFLOW class cannot ship; this is the other class and no instrument sees it. Census of the literal sites and conversion to computed displacements."
---

# A literal displacement is a claim about code someone else emits

Two failure classes, and only one of them is guarded.

- **Too large.** `CheckRel8` hard-errors, 172 sites go through it, and
  [[feature-t-track-the-rel8-displacement-budget-so-a-tight-jump-is-visible-before-it-breaks]]
  warns before it happens. Cannot ship.
- **In range, wrong target.** The span between the jump and its intended
  landing place grew, the displacement is still a legal rel8, and it now points
  into the middle of an instruction sequence. Assembles, links, runs, and
  corrupts. Nothing measures it.

The second one is not hypothetical: it happened, in the shape most likely to
recur — a hand-counted jump over a global store, and `--emit-obj` on i386 later
wrapped every global store in `push`/anchor/`lea`/`pop` to make it position
independent. The wrapper is correct, the store is correct, and the jump that
had counted the old bytes landed on the wrapper's `pop`. It took a
disassembly assertion to see, because no symbol, relocation or size number
moves.

## The job

Enumerate the literal short jumps — frankC's census puts them at roughly 25,
against 172 computed — and convert each to `EmitRel8`/`PatchRel8`, which
computes the displacement from the actual emitted positions and range-checks
it. Enumerate from the EMITTED artifact where possible rather than by grepping
one spelling of the byte-emitting idiom.

The unlock-stub fix also deleted a "this block must be exactly 16 bytes"
assertion, which was the same claim in comment form: a hand-counted constant
standing in for what an emitter will produce. Any sibling assertion of that
shape belongs in this sweep.

## Why it is worth doing rather than watching

A budget row is blind to this class by construction, so the remedy is
structural: make the displacement computed everywhere and the class stops
existing. Until then each one is a correctness bug waiting for an unrelated
emitter to grow — and the growth is normal work, done by someone who has no
reason to look for a jump that spans their edit.
