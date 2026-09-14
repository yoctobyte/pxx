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

### The race is now MEASURED, not inferred

The old reading was that valgrind's serialisation hid a race. That was a
hypothesis from an absence. It is now a positive measurement -- same binary,
same arguments, `--shot --for 20`, four runs:

| run | outcome |
| --- | --- |
| 1 | **rc=0** |
| 2 | rc=134, `malloc(): unsorted double linked list corrupted` |
| 3 | rc=134, `corrupted double-linked list` |
| 4 | **rc=0** |

TWO runs in four SUCCEED and the two failures print DIFFERENT glibc messages.
A deterministic overflow cannot do that; the capture loop steps the sim at a
fixed rate and is otherwise reproducible, so the nondeterminism is coming from
the only other thread in the program -- `lz-tiles`, the daemon started at
`app.py:1251` whose `_loader` reads tiles off the frame.

Length sweep on the same binary, one run each: `--for 12` rc=0, `16` rc=0,
`20` rc=134, `24` rc=134 (`malloc(): mismatching next->prev_size (unsorted)`),
`30` **rc=139**. Three distinct failure modes across five lengths. So the
threshold is not a length at all; longer runs simply give the loader thread
more tiles to deliver and widen the window.

### What has been EXONERATED, so nobody re-walks it

- **The GL seam's out-parameter writers.** Every one passes a plain NAME,
  which is the arm that always worked (`gen_buffer`, `gen_vertex_array`,
  `gen_texture`, `gen_framebuffer`, `gen_renderbuffer`, `read_pixels`,
  `get_shader_iv`, `get_program_iv`, both info-log readers).
- **The sqlite3 blob seam**, which was the best candidate on the owner's own
  original hypothesis -- *"why is a library freeing memory that we allocated"*.
  It does not: `lib/rtl/mimic_sqlite3.pas` binds every blob and text with
  `TransientDtor` (SQLITE_TRANSIENT), so sqlite COPIES and never takes
  ownership of a pxx pointer, and on the way back it copies out of sqlite's
  buffer into a fresh `TPyBytes` rather than aliasing it. Both directions copy.
  Worth knowing because sqlite is the one real C library on the loader thread:
  `world.py:841` opens a connection PER TILE, on the worker.

So the remaining suspect is concurrency itself -- two threads allocating and
releasing through pxx's runtime while a C library (sqlite, then the GL driver)
works its own glibc heap on the same process. `helgrind`/`drd`, not memcheck.

### Thread state at the abort

`gdb -batch`, caught on the first attempt, `--for 20`. No symbols come out of
gdb (the pxx ELF has no section headers), so the PCs are resolved against
`bin/lzfix.map`:

| thread | PC | resolves to |
| --- | --- | --- |
| 1 (main) | `0x7ffff7ca61ac` | inside libc -- this is the SIGABRT, raised by glibc's own malloc consistency check |
| 2 | `0x6280ab` | `PalFutexWaitTimeout + 0xf9` -- parked, not a participant |
| 3 | `0x4dc2eb` | `pynone + 0x25` -- pxx RUNTIME code, not sqlite and not the GL driver |

So at the moment glibc noticed its heap was inconsistent, the worker was
inside pxx's own Python runtime. That does NOT name the corrupter -- glibc
detects corruption long after it happens -- but it does say the crash is not
being taken *inside* a C library call, which is what a "library frees our
pointer" story would need.

The frames above #0 are unusable: no section headers means no unwind info, so
gdb walks garbage. Anything past #0 in that dump should be ignored, which is
also why there is no point re-running this for a deeper stack. **The next
instrument is helgrind or drd, not gdb and not memcheck.**

### Two minimal-stress NEGATIVES, 2026-09-14

The question these were built to answer: **is this lekkerzeilen-specific, or
does pxx's threaded runtime corrupt under concurrent allocation?** A 30-line
NilPy repro would be worth far more than a 20-second GL demo, so it was worth
trying before reaching for helgrind.

Both programs mirror lekkerzeilen's shape -- a daemon worker building objects
off the frame and handing them over a `queue.Queue` while the main thread
allocates too -- and both were built with `--threadsafe`.

| stress | what it adds | result |
| --- | --- | --- |
| `stress.npy` -- pure allocation on both threads | nothing; pxx runtime only | 3/3 clean, 20000 rounds each, 2160-2416 items genuinely crossing the queue |
| `sqlstress.npy` -- a `sqlite3.connect()` and a blob-returning `SELECT` per job on the worker, mirroring `world.py:841` | a real C library on glibc's heap, on the worker thread | 3/3 clean, 400 rounds each, ~220 batches crossing |

**Neither reproduces.** So plain concurrent allocation through pxx's Python
runtime is not sufficient, and neither is adding sqlite on the worker.

Both instruments were checked for the "guard that cannot fail" shape first:
the first version of `stress.npy` printed `drained 0`, which is exactly what it
would also print if the worker thread had never run. It carries a `SEEN`
counter and an explicit `INSTRUMENT DEAD: the worker produced nothing, this run
proves nothing` line now, and the item counts above are what that counter
reports -- the runs are live, not silently empty.

**What is left, and it is the axis neither stress has:** the main thread being
inside the GL driver (`libGL.so.1`) at the same time the worker allocates. That
is the one ingredient lekkerzeilen has that a headless NilPy program does not,
and it is not reachable from a minimal repro without bringing SDL and a context
along -- at which point it is not minimal any more.

### sqlite3 ownership, closed out

The exculpation above was on the blob COPY direction. The ownership question is
now closed on all four counts, against `lib/rtl/mimic_sqlite3.pas`:

- `TransientDtor` really is `Pointer(-1)` = `SQLITE_TRANSIENT`, so every bound
  text and blob is copied by sqlite before the call returns -- we never hand it
  a pxx pointer to keep (`:265`, call sites `:510`, `:511`, `:528`).
- `sqlite3_free` is called at exactly ONE site, `:454`, on the `errmsg` that
  `sqlite3_exec` itself allocated. We never free a pxx pointer through it, and
  we never `FreeMem` a sqlite one.
- `sqlite3_open_v2` passes no `SQLITE_OPEN_NOMUTEX`, so connections are in
  sqlite's default serialized mode.
- The system library answers `sqlite3_threadsafe() = 1` (3.46.1), i.e. built
  serialized.

**That is the owner's original hypothesis -- "why is a library freeing memory
that we allocated" -- refuted for the only library where we could plausibly
have done it.** The remaining `DT_NEEDED` are `libc.so.6`, `libSDL2-2.0.so.0`
and `libGL.so.1`, and we hand none of those a pointer to own.
