---
slug: bug-n-a-star-argument-releases-a-sequence-it-only-borrowed
title: a star argument released the sequence it only borrowed, freeing it while still referenced
summary: >
  `f(*xs)` lowers to a hidden class-typed local holding the operand as a
  TPyList, and that local is released at scope exit. `pystar_as_list` filled it
  from TWO conventions: a list or a tuple was handed "straight back" BORROWED,
  anything else was drained into a fresh OWNED list. So every star call whose
  operand is a VARIANT -- which is every unannotated parameter -- released a
  sequence it only borrowed, drove its refcount below zero, and freed a block
  something else still pointed at. Fixed by retaining on the borrowed arm, so
  both arms return owned. On lekkerzeilen this moved the world path from SIGSEGV
  in App._build_structures to reaching the FRAME LOOP: rc 139 -> 217, dying on
  an already-ticketed unrelated bug. Fixture
  test_nilpy_a_star_argument_does_not_release_the_sequence_it_borrows, guarded
  by the new tools/assert_no_rc_underflow.sh.
track: N
type: bug
prio: 90
owner: frank-user
status: done
---

## Minimal

    def three(x, y, z):
        return x + y + z

    def spread(a):
        return three(*a)

    def make():
        return spread((1.0, 2.0, 3.0))

    print(make())

Prints `6.0` on both compilers. The defect is one release too many on the
tuple, and `-dPXX_OBJTRACE` is the only thing that can see it.

`spread(a[0], a[1], a[2])` is clean. `def make(): a = (1.0, 2.0, 3.0); return
three(*a)` is clean -- a statically-typed local takes the non-variant arm of
`PyStarOperandAsList` and never goes through `pystar_as_list` at all. At MODULE
level it is also clean, because the operand outlives the frame and the count
never reaches zero: that is why this needed a function to show at all.

## The code, and it says so itself

`pystar_as_list` (pylib.pas), comment unchanged since it was written:

    { a list (or a tuple, which is the same object) is handed straight back —
      the packing only READS it, so a copy would be pure cost }

True about the packing, and the packing is not the only consumer.
`PyStarExpandCallArgs` assigns the result into `$starl`, a class-typed hidden
local, which is released when the frame ends. The other arm --
`pyiter_drain(pyiter_v(v))` -- returns a fresh list, so one function returned
borrowed down one arm and owned down the other, and the caller cannot tell.

Same shape as `bug-n-a-set-comprehension-over-releases-its-own-list`, landed
four hours earlier: an identity-ish helper returning a BORROWED reference into a
slot that owns. The fix is the opposite one, and that is not inconsistent --
there the helper had four call sites under two conventions so the sites had to
move; here it has one conventional consumer, so the helper moves.

## How it was found

Whole-demo `-dPXX_OBJTRACE`: 3151 underflow events over 2184 addresses. A
temporary fatal trap in `PXXObjRelease` behind `-dPXX_UFTRAP` stopped at the
FIRST one; the stack resolved (offline, against the .map -- `bt` lies here) to
`PXXObjRelease` <- `Vessel.create`, in the constructor's epilogue.

**`bt` named a frame that was never entered.** gdb printed
`Vessel.create (self=0x7fffd69d1c68, ...)` with half its arguments
`<error reading variable>`, and a conditional breakpoint
`break Vessel.create if (unsigned long)self == 0x7fffd69d1c68` never fired --
no Vessel ever had that address. The frame was a reconstruction from stale
stack. The offline resolution of the same stack was right.

Then bisected in a scratch copy of the demo by inserting an early `return`
at each statement of `Vessel.__init__`, rebuilding, and counting underflows on
a probe that builds ONE Vessel and nothing else:

    return before line 217  underflow=0
    return before line 225  underflow=0
    return before line 239  underflow=1     <- self.hull_drag = sim.HullDrag(...)

then the same inside `sim.HullDrag.__init__`, which landed on line 239,
`self.angular = Vec3(*angular)`. Replacing that one line in place decided it:

    self.angular = Vec3(*angular)                            underflow=1
    self.angular = Vec3(angular[0], angular[1], angular[2])  underflow=0
    _t = tuple(angular); self.angular = Vec3(*_t)            underflow=0
    self.angular = Vec3(*angular) twice                      underflow=2

Six standalone guesses at the shape had all come back clean first. The
in-place bisect is what worked, and it is cheaper than it sounds: a probe that
imports the package and builds one boat rebuilds in seconds.

## Measured, both directions

Twenty rows -- the star matrix, the constructor shapes, the earlier negatives.
Every underflow went to zero and **`live_at_exit` is identical on all twenty**,
which is the check the set-comprehension work taught: the first candidate there
zeroed the underflows and leaked on a row that was already clean.

## What it did for the demo

    before   rc=139  SIGSEGV in App._build_structures -> Mesh.add_instances
                     -> sum -> pylist_v -> pyseq_of_obj -> __pxxInheritsFrom
                     on a pointer whose bytes were x86 instructions
    after    rc=217  loads the world, prints the structures, the water block and
                     the traffic line, opens the window, reaches the FRAME LOOP,
                     and raises
                     `TypeError: not all arguments converted during string formatting`

That last one is `bug-n-adjacent-string-literals-splice-a-plus-so-a-tighter-operator-binds-wrong`
at app.py:4033, measured by lekkerzeilen-c8 and already open. Deterministic
under `setarch -R`, with and without gdb.

## Guard

`test_nilpy_a_star_argument_does_not_release_the_sequence_it_borrows`, wired
with TWO Makefile rows.

**The value row cannot fail on this defect and is not meant to.** The extra
release lands after the last read, so the unfixed compiler prints exactly the
expected lines; that row is there so a repair cannot buy the refcount back by
breaking the semantics. The guard is the second row: built `-dPXX_OBJTRACE` and
run through the new `tools/assert_no_rc_underflow.sh`, which counts releases
that drive a refcount below zero -- **6 unfixed, 0 fixed**. Every star call in
the fixture is made from inside a function on purpose.

## Log
- 2026-09-14 — resolved, commit eb9228950.
