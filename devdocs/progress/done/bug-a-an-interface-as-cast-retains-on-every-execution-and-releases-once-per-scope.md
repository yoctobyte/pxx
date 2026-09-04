---
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: frankb-78
summary: "FIXED 2026-09-04. `obj as IFoo` AddRefs the temp it materialises, and that temp is memoised per cast SITE rather than per execution -- so a cast in a loop retained a different object into the same word every trip and released only the last. Everything else leaked AND ITS DESTRUCTOR NEVER RAN. Measured against the FPC oracle on identical source: 5 casts in the main body destroyed 4 under FPC and 0 under pxx; 3 inside a procedure, 3 versus 1. Fixed by releasing the temp's previous value before overwriting it, inside the same COM condition as the AddRef. Distinct from feature-a-getinterface-refcounting, which is the opposite sign -- a MISSING retain."
---

# An interface `as`-cast retains on every execution and releases once per scope

Found by frankb-78 while attempting the target of
`umbrella-managed-memory-is-correct` — ten common managed-memory constructs
looped 2000 and 8000 times under `-dPXX_ALLOC_CENSUS`, slope as the measurement.
Nine were flat. This one was not.

## The measurement

`IRMaterializeIntfCast` builds the interface value into a hidden temp and calls
`PXXIntfAddRef`, because a QueryInterface returns an owning reference; the temp
is released at the enclosing routine's scope exit (or at end of main for a
main-body temp). Both halves are deliberate and both are documented in the code.

What neither accounts for is that the temp is **memoised in `ASTLiftedVar` —
one slot per cast SITE, not per execution.** A site inside a loop stores a
different instance into that one word every trip, without releasing what was
there. So the retain runs N times and the release once.

**The leak is the boring half. The destructor not running is the bug**, and no
output assertion or leak bound catches that on its own — the objects are
reachable-and-never-freed. Against the FPC oracle, identical source, a
destructor counting its own calls:

| row | FPC | pxx before | pxx after |
| --- | --- | --- | --- |
| 5 casts in the main body | 4 | **0** | 4 |
| 3 casts inside a procedure | 3 | **1** | 3 |
| 5 objects, no cast at all | 5 | 5 | 5 |

Census slope agrees: **0.973 blocks per iteration** in the main body,
**1.871 per call** for three casts in a procedure (three retains, one release —
two lost), flat after.

Row three is the control that makes the other two readable: the implicit
class→interface coercion (`q := TThing.Create`) goes down the ordinary
managed-assignment path, which already releases the slot's previous value. It
was correct all along, and without it `5 5 5` and `0 1 5` are equally consistent
with a destructor that never increments.

Main-body 4-of-5 is not an off-by-one. The cast temp legitimately still holds
the fifth object when the count prints and is released at end of main; FPC
answers 4 for the same reason.

## The fix

Release the temp's previous value immediately before the store that overwrites
it, **inside the same COM condition as the AddRef** — a non-COM interface never
retained here and must not release. Safe on the first execution because the slot
starts nil (BSS for a main-body temp, prologue-zeroed for a local — the same
guarantee `EmitManagedLocalCleanup` already relies on when it releases these
temps at scope exit) and `PXXIntfRelease` is nil-safe.

Guard: `test/test_interface_as_cast_temp_released_per_execution.pas`, wired for
x86-64. Positive control: pin v403 prints `0 / 1 / 5`.

## Not the same bug as `feature-a-getinterface-refcounting`

That one is a **missing** retain — `__pxxGetInterface` stores a borrowed pointer
into a managed slot, so `Supports` is one release against zero retains, and its
failure mode is an EARLY FREE. This one is a retain firing too often, and its
failure mode is a destructor that never runs. Opposite signs, opposite symptoms,
and folding them would make one ticket whose fix is two fixes. They do share a
subsystem, so whoever takes the other one should read this first.

## Cross targets — measured, not argued

The argument for skipping this was good: the lowering is shared (`ir.inc`) and
the emitted call is an ordinary `PXXIntfRelease` every backend already emits for
scope-exit cleanup, so there is no target-specific arm. The argument is also
exactly the shape that has been wrong here before, and running it cost a minute.

`i386`, `aarch64`, `arm32`, `riscv32` and `xtensa` all build the guard and
produce output IDENTICAL to the x86-64 oracle — `4 / 3 / 5` on every one.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 4db0446a4.
