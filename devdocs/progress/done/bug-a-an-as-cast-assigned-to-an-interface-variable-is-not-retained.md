---
track: A
prio: 65
type: bug
blocked-by: []
summary: "`f := b as IFoo` moved the interface pointer with no retain, so three holders shared two counted references and the object died one release early. The scope-exit release of the as-cast temp then ran on freed memory — a latent use-after-free that turned into a SEGFAULT as soon as a later statement allocated over the block."
status: done
owner: claude-acp
---

# An as-cast assigned to an interface variable is not retained

- **Track A** (`compiler/ir.inc`, the ARC assignment path).
- Found 2026-08-20 by an FPC differential probe of the interface surface — the
  probe produced *all* of its expected output and then crashed at exit.

## Measured

```pascal
b := TBar.Create('g');
f := b as IFoo;
b := nil;
f := nil;
writeln(destroyed);     { FPC: 0 — the as-cast temp still holds a reference }
                        { pxx: 1 — destroyed one release too early }
```

Add any later allocation and the exit release of the temp walks a freed object:

| | FPC | pinned pxx |
| --- | --- | --- |
| as-cast, then a `Supports` call on a fresh object | clean, exit 0 | all output printed, then **SIGSEGV**, exit 139 |

## Cause

The ARC assignment path routes an interface-to-interface assignment through
`PXXIntfAssign` (retain source, release old dest, copy) only when the RHS node
kind is one of an **enumerated list**: `AN_IDENT`, `AN_FIELD`, `AN_INDEX`,
`AN_DEREF`. `AN_AS_CAST` was not in the list, so an as-cast RHS fell through to
the generic 16-byte record copy, which moves the pointer raw.

`b`, the hidden as-cast temp, and `f` then held three aliases of two counted
references. `b := nil` and `f := nil` spent both, the object was destroyed, and
`EmitManagedLocalCleanup`'s release of the temp ran on freed memory.

This is the `normalise-dont-special-case` shape, and specifically the sibling
that section tells you to grep for: it was found *because* the by-value-param
leak fixed the same morning had the same signature — one concept, several
node-kind-keyed paths, and the one nobody enumerated stays broken.

## Fix

Add `AN_AS_CAST` to the list. `IRLowerAddress` already materialises an interface
as-cast into an addressable fat-pointer temp, so no new address path was needed.

The ownership rule the list encodes, now written down in the code: **an lvalue is
a BORROW and must be retained; a call result is already OWNED and must not be.**
An as-cast is a borrow from its own temp (`IRMaterializeIntfCast` retains that
temp, scope exit releases it), so it retains like the other four. The test pins
the call-result arm too, so a future fix cannot over-retain it instead.

## Why it looked harmless

On its own the symptom is "an object is destroyed earlier than FPC destroys it",
which reads as a finalization-TIMING difference — and this repo has several real
ones (`bug-pascal-mainbody-ascast-temp-finalization-timing`). It is not: it is a
missing retain, and the dangling release is only invisible until the block is
reused. **A refcount that is off by one and a lifetime that is merely early look
identical until you allocate over the corpse.**

## Test

`test/test_interface_as_cast_retains.pas` — 7/7, byte-identical to FPC. Covers
the as-cast borrow, the call-result owned case, an ordinary lvalue borrow, and
the allocate-over-the-corpse shape that actually crashed. The pinned binary fails
row 1 and then segfaults.

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
