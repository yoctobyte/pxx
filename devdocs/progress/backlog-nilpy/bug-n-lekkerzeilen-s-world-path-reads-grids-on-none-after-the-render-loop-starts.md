---
slug: bug-n-lekkerzeilen-s-world-path-reads-grids-on-none-after-the-render-loop-starts
title: lekkerzeilen's world path reads .grids on None once the render loop starts
summary: >
  SUPERSEDED IN PART, 2026-09-14 -- RE-MEASURE BEFORE WORKING THIS. Two bytes
  bugs in the C seam have been fixed since this was filed (no NUL terminator on
  a bytes payload; a bytes EXPRESSION in a C-seam argument passing the object
  header instead of its buffer), and the world path now RENDERS and exits
  rc=0 -- `--shot --for 12`, which used to abort, produces a 772KB picture of
  the Rhine corridor. What survives is the glibc heap corruption at longer
  runs: `--for 30` still aborts with `malloc(): unsorted double linked list
  corrupted`. The `.grids`-on-None reading in this ticket was taken under
  valgrind on a binary that no longer exists and has NOT been re-measured;
  treat it as unverified until someone re-runs it.
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

## 2026-09-14 -- re-measured after the two bytes fixes

`lz/bin/lzfix`, compiler at the bytes-expression fix, pristine lekkerzeilen
sources:

| run | before | now |
| --- | --- | --- |
| `--open-water --shot X --for 5` | rc=0, a 6901-byte EMPTY image | rc=0, a 514KB picture of a launch on open water |
| `--shot X --for 8` (world) | not reached | rc=0, a 762KB picture of the Rhine corridor |
| `--shot X --for 12` (world) | **rc=134**, `malloc(): unsorted double linked list corrupted` | **rc=0**, 772KB |
| `--shot X --for 30` (world) | -- | **rc=134**, same glibc message |

So the abort has moved out, not gone. A live hypothesis for the remainder,
and it is the one this ticket should be worked from: the ir.inc comment on
`bug-n-a-bytearray-bound-to-a-c-pointer-parameter-passes-the-object-pointer-not-the-data`
records that a WRITER through that path *destroys the VMT* -- `pipe(b)` put
fd 3 and fd 4 over the object header. A glibc heap abort is exactly what a
C callee writing into a pxx object header produces. The fix that landed today
covers a bytes reaching an EXTERNAL routine's pointer parameter as an
expression; anything still reaching one by a route neither that arm nor
IRLowerCallArg's static arm can see would have the same signature.

**That search has already been done for the GL seam and came back EMPTY --
recorded so nobody repeats it.** Every writer in `platform/_pxx.py` passes a
plain NAME, which is the arm that always worked: `gen_buffer`,
`gen_vertex_array`, `gen_texture`, `gen_framebuffer`, `gen_renderbuffer` each
do `buf = bytearray(4); glGen*(1, buf)`; `read_pixels` does
`buf = bytearray(w*h*3); glReadPixels(..., buf)`; `get_shader_iv`,
`get_program_iv` and both info-log readers do the same. So the remaining abort
is NOT the seam's out-parameter calls, and it is not the bug that landed
today. Next candidates: SDL's event buffer, the threading path (the run is
`--threadsafe` and the old reading was that valgrind's serialisation hid a
RACE), and anything that keeps a pointer INTO a bytes across a call.

The `.grids`-on-None row above is from a binary built before any of this and
is not evidence about the current one.
