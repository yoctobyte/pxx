---
slug: bug-n-lekkerzeilen-s-world-path-reads-grids-on-none-after-the-render-loop-starts
title: lekkerzeilen's world path reads .grids on None once the render loop starts
summary: >
  With the classref RTTI walk and the bound-method return ABI both fixed, the
  world path loads, renders the 512x512 chart, enters the frame loop, and then
  raises `AttributeError: 'NoneType' object has no attribute 'grids'`. Under
  valgrind the run is MEMORY-CLEAN -- no invalid read or write anywhere, only
  uninitialised-value reads (3 contexts in the app, 2 in the NVIDIA driver) --
  so this is a wrong VALUE, not corruption. Without valgrind the same binary
  instead aborts on `malloc(): unsorted double linked list corrupted`, which
  valgrind's thread serialisation hides: that is a separate RACE and has its
  own ticket line below.
track: N
type: bug
prio: 75
owner: unassigned
status: open
---

## What is measured

`lz/bin/lzbr`, built from compiler 0dd33e07b076 (both fixes in):

| run | outcome |
| --- | --- |
| plain | rc=134, `malloc(): unsorted double linked list corrupted` |
| under valgrind | rc=217, `AttributeError: 'NoneType' object has no attribute 'grids'`, ERROR SUMMARY 310 errors from 4 contexts, **none of them an invalid read or write** |

Both are AFTER the chart renders and the controller is bound, i.e. inside the
frame loop. For contrast, before these two fixes the same path died at ~5.7 s
in `PyBoundPairCallKwBody` (rc=139) and, before that, in `__pxxInheritsFrom` on
the loader thread.

## Two separate things, do not merge them

1. **The None.** `self.grids` lives on `Region` (world.py:183, read at 318,
   335, 341, 346). A method reaching those lines with `self` = None means a
   caller is holding a None region. `isinstance` against a module-qualified
   class is NOT the cause -- a three-row reduction (`direct`, `through a
   function`, `negative`) is byte-identical to CPython, so
   `app.py:624`'s `region if isinstance(region, world.World) else None` is
   not silently taking its else arm in the simple shape. Where the None comes
   from is the open question.
2. **The race.** Memory-clean under valgrind and heap-corrupting without it is
   the signature of a thread race, and the loader runs on a worker
   (`PalThreadCreate -> ThreadLauncher -> pybound_callv0 -> App._loader`).
   valgrind serialises threads, which is exactly why it disappears there.
   Needs helgrind or drd, not memcheck.

## Where to start

For (1): instrument which call site passes the None rather than reading
world.py -- the frames are compiler-generated in this area and the Python does
not name the failing receiver. For (2): `valgrind --tool=helgrind` on the same
binary, and check whether anything crosses the loader/render thread boundary
without a lock.

## Log
- 2026-09-14 -- reached after
  `done/bug-n-a-class-reference-receiver-walks-rtti-off-a-non-instance` and
  `done/bug-n-a-callable-value-called-with-four-arguments-dereferences-a-variant-at-address-1`
  moved the world path past two earlier walls. Each fix that makes a call
  complete exposes the layer the incomplete call was hiding; this is the third
  instance in one evening.
