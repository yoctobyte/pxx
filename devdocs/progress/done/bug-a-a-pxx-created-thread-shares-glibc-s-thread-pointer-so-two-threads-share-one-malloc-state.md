---
slug: bug-a-a-pxx-created-thread-shares-glibc-s-thread-pointer-so-two-threads-share-one-malloc-state
title: a pxx-created thread shares glibc's thread pointer, so two threads share one malloc state
summary: >
  `PXX_CLONE_THREAD` omits `CLONE_SETTLS`, so every thread pxx creates inherits
  the parent's `fs` base -- glibc's thread pointer. glibc's malloc keeps its
  per-thread state there and takes no lock on it, because it is per-thread by
  construction. So as soon as a pxx-created thread and the main thread both
  call into any C library that allocates, they operate one malloc state
  concurrently and corrupt glibc's heap. Measured 5/5 with a 60-line Pascal
  repro; the same churn single-threaded is 3/3 clean and the same churn with the
  worker created by `pthread_create` is 5/5 clean. Disabling glibc's tcache does
  NOT rescue it, so there is no env-var mitigation. This is what aborts the
  lekkerzeilen demo.
  FIXED 2026-09-14 ON x86-64, and NOT by adding CLONE_SETTLS: palthread.pas
  imports pthread_create/pthread_join as `weakexternal` and lets glibc make the
  thread whenever they resolve, so glibc owns the fs base because glibc created
  it. The child trampoline installs pxx's own gs block and alt stack the way the
  clone stub's child leg does. The route is chosen at RUNTIME, so a libc-free
  static program resolves nothing and keeps the clone path byte-for-byte. The
  repro goes 5/5 rc=134 abort -> 5/5 rc=0. The other four targets still carry the
  hazard:
  bug-a-a-cloned-thread-still-inherits-the-parents-fs-base-on-every-target-but-x86-64.
track: A
type: bug
prio: 85
owner: unassigned
status: resolved
resolved: 2026-09-14
---

## The mechanism

`lib/rtl/palthread.pas:92`:

```pascal
{ thread clone flags: VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID. }
PXX_CLONE_THREAD = $350F00;
```

Decoded, and the flags account for the constant exactly with nothing left over:
`CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD |
CLONE_SYSVSEM | CLONE_PARENT_SETTID | CLONE_CHILD_CLEARTID`. **`CLONE_SETTLS`
(0x80000) is not among them**, which is deliberate and documented --
`devdocs/dev/threading.md:221` says so in as many words.

That file then solves pxx's OWN thread-local problem by having each thread
install its own block in **`gs`** via `arch_prctl(ARCH_SET_GS)`, and its "GS,
not FS" section explains, correctly and from a measurement, why taking `fs`
was catastrophic: it destroyed libc's TLS for the main thread and a four-line
program calling `printf`/`malloc` segfaulted.

**What that reasoning does not carry is the other half.** Not taking `fs` is
right; leaving it INHERITED is what this ticket is about. A cloned thread gets
the parent's `fs` base, so every glibc thread-local is SHARED between the main
thread and every thread pxx creates -- `errno`, and, the expensive one,
malloc's per-thread state. glibc treats that state as private to a thread and
therefore takes no lock on it.

Two threads, one malloc state, no lock. That is the whole bug.

## Repro, and it is small

`test/thread_glibc_malloc_two_threads.pas` (added with this ticket). Two
threads do nothing but `malloc`/`free` from `libc.so.6`, 400000 rounds each,
sizes 24..792 bytes.

| run | | |
| --- | --- | --- |
| the repro, worker from `PalThreadCreate` | **5/5 abort** | `free(): too many chunks detected in tcache` |

glibc names the structure itself.

## The two controls, and they are what make this conclusive

`test/thread_glibc_malloc_controls.pas`, same file, same churn, same libc,
same machine.

| control | what differs | result |
| --- | --- | --- |
| **A** -- one thread, 800000 rounds (twice the work) | no second thread | 3/3 survive |
| **B** -- two threads, worker created by glibc's own `pthread_create` | who created the thread, and nothing else | 5/5 survive |

Control A says the churn is not the defect. Control B says the *concurrency*
is not the defect either: a `pthread_create` thread gets `CLONE_SETTLS` and its
own `fs` block, hence its own malloc state, and the identical program survives.
**One variable separates 5/5 abort from 5/5 clean, and it is which call
created the thread.**

## There is no env-var mitigation, and this is worth knowing before anyone tries

The obvious first thought is that the tcache is the whole story -- it is the
lock-free part of glibc's malloc -- and that
`GLIBC_TUNABLES=glibc.malloc.tcache_count=0` would therefore paper over it.
Measured on the same binary: **it does not.** Five runs gave four SIGSEGV and
one `double free or corruption (out)`. The tunable is innocent -- controls A
and B were re-run under it and are still 2/2 and 3/3 clean -- so what it shows
is that the shared state is larger than the tcache. glibc's `struct pthread`
itself is reachable from `fs`, and lock ownership is read out of it, so two
threads that agree on `THREAD_SELF` are not merely racing a free list.

Anyone reaching for a runtime knob should read this row first.

## What it looks like when it bites

Silently, in a program with no threading bug of its own, far from the cause,
and only when a C library is on both threads.

The lekkerzeilen demo (goal 3) is the live case. Measured 2026-09-14 on the
same binary and the same length:

| run shape | result |
| --- | --- |
| `--shot X --for 20` with a world (a tile loader thread doing sqlite; the main thread in SDL/GL) | **4/5 abort**, three different glibc messages: `malloc(): unsorted double linked list corrupted`, `corrupted double-linked list`, `corrupted size vs. prev_size` |
| `--open-water --shot X --for 20` (no region, hence no TILE LOADER -- but see the correction below) | **5/5 clean** |

Two minimal NilPy stresses had already come back clean and are recorded in
`bug-n-lekkerzeilen-s-world-path-reads-grids-on-none-after-the-render-loop-starts`:
pure allocation on both threads (pxx's heap is mmap-backed and never reaches
glibc, so there is nothing to corrupt), and sqlite on the worker with only pxx
allocation on the main thread (**one** thread in glibc malloc, so still no
collision). Both negatives are consistent with this cause and neither could
have found it -- **the defect needs a C library on BOTH threads**, which is
the one shape a headless minimal repro does not fall into by accident.

## The demo itself, with the thread taken out

The repro above is 60 lines of Pascal. This is the same claim made end to end,
in the application, by removing the second thread and changing nothing else:
a scratch copy of lekkerzeilen with `_loader` moved onto the MAIN thread (the
loader's body, drained synchronously where the orders are submitted; the
`_ready` queue unbounded so a synchronous pump cannot deadlock on `maxsize=2`).

| build | world, `--shot --for 20` |
| --- | --- |
| loader on its own pxx thread | **5/5 abort**, and no image is written at all |
| loader on the main thread, everything else identical | **5/5 rc=0**, a ~739KB image every time |

Both built from the same entry point with the same flags, from the same
sources apart from the loader patch, so the comparison is not across build
commands -- the earlier 4/5 figure in this ticket's history came from
`bin/lzfix`, which was built from a different source file, and the matched
control is worse, not better. The threaded side's five runs give two distinct
messages (`corrupted double-linked list` once, `malloc(): unsorted double
linked list corrupted` four times), which is itself the signature: a
deterministic bug does not choose between two messages.

The scratch patch is an EXPERIMENT and is not a proposed change to the
application -- it exists to move one variable.

## THE DRIVER PATH FLIPS IT, AND A HARNESS THAT FORCED WAYLAND HID IT FOR A DAY

Two seats measured this demo all day and got irreconcilable numbers -- 5/5 abort
here against 13 green rows there -- on the same box, from pristine source, at
the same compiler sha. The difference was one environment variable in the other
seat's harness, hardcoded since the start.

`SDL_VIDEODRIVER`. Same pristine binary, same `--shot FILE --for 20`, ASLR on:

| harness | wayland | x11 | unset |
| --- | --- | --- | --- |
| this seat, `bin/lzthreaded` | **5/5 rc=0** | **3/5 abort** | -- |
| `lekkerzeilen-c8`, its own build | **0/10 abort** | **5/9 abort** | 1/5 abort |

Two independent binaries, two harnesses, same conclusion. The `unset` row is
why this went unnoticed: both seats' environments carry BOTH
`WAYLAND_DISPLAY=wayland-0` and `DISPLAY=:0`, so SDL chooses, and the choice is
not stable across harnesses.

### FOUR distinct ways to die, and all four are ARENA STRUCTURE checks

Across both harnesses, eleven aborts, four different glibc messages:

| message | seen by | what check it is |
| --- | --- | --- |
| `malloc(): unsorted double linked list corrupted` | both | the unsorted-bin walk in `_int_malloc` |
| `corrupted double-linked list` | peer, x2 | `unlink_chunk`'s fd/bk agreement |
| `corrupted size vs. prev_size` | this seat | adjacent chunks disagreeing about their own boundary |
| `malloc(): largebin double linked list corrupted (nextsize)` | this seat | the largebin `nextsize` chain on insertion |

A deterministic bug does not choose between four ways to die, so the spread is
the race. **But the more useful half is that the four are not a random
assortment.** Every one of them is glibc discovering that ITS OWN bookkeeping
no longer agrees with itself -- bin links, chain links, chunk boundaries. Not
one of them is a bad pointer arriving from the program.

That distinction matters because it is the discriminator against the other
hypothesis this ticket started from. **"A library is freeing memory we
allocated"**, or pxx header arithmetic landing on a glibc chunk, produces an
invalid POINTER, and glibc reports those differently (`free(): invalid
pointer`, `munmap_chunk(): invalid pointer`). Four different structure-integrity
checks failing, and no pointer complaint in eleven aborts, is what two threads
interleaving inside one unlocked arena produces and is hard to produce any
other way.

The peer's count above is a correction to its own earlier row: it had reported
one message and had two, because a second batch's `.err` files were written,
were correct, and were never opened -- it had gone in for the stdout tail and
got it. **An instrument you only HALF-READ is its own failure mode**, distinct
from an inert one or a stale one, and the cheapest of the day to avoid.

The other seat also placed the death: 16.0-23.5 s wall, always between the
first stdout line and `chart 512x512 ...`, which is `settle()`'s window -- the
loader on sqlite while the main thread drives GLX. Both allocating, one arena.

**Reading, not measurement:** EGL/Wayland appears to do less main-thread
allocation through this window than GLX/XWayland does, and fewer main-thread
mallocs concurrent with the loader means fewer chances to interleave inside an
arena operation. Nobody has instrumented the allocation counts. The FINDING is
only that the driver path flips it.

**The lesson is about harnesses, not about SDL.** `SDL_VIDEODRIVER=wayland` was
not a deliberate variable -- it was scaffolding, set once and never revisited,
and it silently removed the condition under test from every row that harness
produced. Those rows were not wrong; they were correct about the wayland path
and silent about the other one, which is indistinguishable from "the bug is not
there" unless someone varies it. **Before trusting a green sweep, list what
your harness PINS that the defect might live on.**

## WARNING for anyone re-measuring: two of glibc's debug knobs are INERT here

Measured 2026-09-14 on Ubuntu GLIBC 2.43, with a deliberate double-free in C
as the subject:

| env | what the double free says |
| --- | --- |
| none | `free(): double free detected in tcache 2` |
| `MALLOC_CHECK_=3` | `free(): double free detected in tcache 2` -- **identical** |
| `GLIBC_TUNABLES=glibc.malloc.check=3` | `free(): double free detected in tcache 2` -- **identical** |
| `LD_PRELOAD=libc_malloc_debug.so.0 MALLOC_CHECK_=3` | `free(): invalid pointer` -- the mcheck path, reached at last |

`MALLOC_PERTURB_` is inert the same way: freed bytes past the tcache header
read back unchanged with it set. Since glibc 2.34 both live in
`libc_malloc_debug.so`, which must be preloaded.

**Neither errors. Both answer.** A run "under `MALLOC_CHECK_=3`" on this box is
a plain run wearing a label, and "the checker did not convert it to an abort"
is not a fact about the program. Reading such a row as evidence about a crash's
nature is the house failure mode exactly.

`glibc.malloc.tcache_count` IS live and the rows above that use it stand:
`tcache_count=0` changes the double-free message to `double free or corruption
(top)`, and a deliberately BOGUS tunable name leaves it unchanged -- which is
the control that separates "the tunable did something" from "the string was
accepted".

## CORRECTION 2026-09-14: IT IS NOT THREAD COUNT, IT IS WHO CALLS INTO C

This ticket first explained the clean `--open-water` row as "no loader thread,
therefore no second thread". **That reasoning is wrong and the row is still
right**, which is the dangerous combination -- a reader would come away with
"avoid threads" when the actual rule is narrower and cheaper to obey.

`--open-water` is not single-threaded. Measured by thread name, which separates
ours from theirs for free: **a raw `clone` sets no `comm`, so a pxx-created
thread inherits the PROCESS name, while every library thread created through
`pthread_create` names itself.**

| mode | threads named `lzthreaded` (OURS) | named threads (gmain, gdbus, pool-0, ...) |
| --- | --- | --- |
| `--open-water` | **2** -- main plus one | 9 |
| world | **4** -- main plus three | 9 |

So open water runs a pxx-created thread of its own and is clean 5/5 anyway, and
the nine library threads are irrelevant in both modes -- they got `CLONE_SETTLS`
from glibc and have their own malloc state.

**The condition is not "more than one thread". It is "more than one thread
ALLOCATING THROUGH A C LIBRARY".** The tile loader qualifies: it opens a sqlite
connection per tile (`world.py:841`). Whatever open water's second pxx thread
does, it does not do that while the main thread is in the driver.

That is exactly the repro's condition and it is why the repro is two threads
doing nothing but `malloc`/`free` -- and it is also why the two NilPy stresses
came back clean: one had no C library at all, and the other had sqlite on the
worker with only pxx allocation on the main thread, which is ONE thread in
glibc malloc, not two.

**Practical consequence, and it is the mitigation to give anyone who hits this
before the PAL is fixed:** keep C-library calls on one thread. Not "do not
thread".

### And `--threadsafe` is not the missing flag -- the compiler will not let you omit it

Asked directly, and worth recording because it is the first thing anyone
sensible checks. Building the repro WITHOUT `--threadsafe`:

```
pascal26:199: error: __pxxclone (thread creation) requires --threadsafe or
{$threadsafe on}: the default heap/ARC/console-I/O runtime is not thread-safe
```

You cannot produce a threaded pxx binary by accident; the guard fires at the
clone site. lekkerzeilen's own `runbin.sh` passes it, and every measurement in
this ticket was built with it. `--threadsafe` makes **pxx's** heap, ARC and
console I/O thread-safe, and that machinery works. It has nothing to say about
**glibc's** malloc, which is a different allocator in a different library --
which is the whole point of this ticket.

## Blast radius

Every `--threadsafe` pxx program that links any C library and allocates on
more than one thread. That is not an exotic set: `lib/rtl` binds
`libsqlite3.so.0`, and any SDL/GL/curl/zlib seam is the same shape. The
corruption is in glibc's heap, so `-dPXX_HEAP_DEBUG` is blind to it by
construction (pxx's heap is mmap-backed and never calls glibc malloc) --
see the `pxx heap vs glibc heap` note.

It also means `errno` is shared across pxx threads, which is a second,
quieter defect from the same cause. Not measured here; named so it is not
rediscovered separately.

## The fork, and why it is not being taken in this session

Stated without an implementation noun: **when a pxx program links a C library
and creates threads, should those threads be full citizens of that C library's
runtime?** Everything below assumes the answer is yes; if it is no, the honest
outcome is a documented refusal rather than silent corruption.

Two routes, and they differ in what we are trying to be:

1. **Route thread creation through `pthread_create` when glibc is linked.**
   Correct by construction -- glibc builds its own TCB and nobody has to model
   `struct pthread`. Costs: it inverts `lib/rtl/palpthread.pas`, which today
   *provides* `pthread_create` on top of `PalThreadCreate` for libc-free
   programs, so the two directions must not collide; and the `TidWord` join
   handshake (`CLONE_PARENT_SETTID`/`CLONE_CHILD_CLEARTID`) has no equivalent
   and would need a parallel `pthread_join` path. It also makes threading
   depend on libc for programs that link it, which is a real change in what pxx
   is -- static, libc-free, writing its own ELF.
2. **Pass `CLONE_SETTLS` with a synthesised glibc-compatible TCB.** Keeps the
   clone path and the existing handle contract. Costs: `struct pthread` is
   private and versioned, and getting it subtly wrong breaks `errno`, the stack
   canary at `fs:0x28`, locale and stdio -- the exact failure `threading.md`
   already recorded once, arriving silently instead of loudly.

There is a third position worth stating because it is cheap and may be right
for now: **detect and refuse.** If a program links libc and creates a pxx
thread, say so at compile time. That converts a silent heap corruption into a
diagnostic, which is strictly better than today even if neither route above is
ever built.

Recommendation: route 1, gated on libc actually being linked, with route 3 as
the interim. Not taken here because it is a day of work in the PAL with a
`palpthread.pas` collision to resolve, and because the fork above is a real one.

## Route 2 was MEASURED, not reasoned about -- and it is narrowed, not cleared

The fork above should not cost whoever takes it a day of ABI archaeology to
find out where route 2 stops being cheap. It was probed directly: a scratch
build in which the child thread, as its FIRST act, mmaps a block and installs
it with `arch_prctl(ARCH_SET_FS)` -- the same mechanism `palthread.pas`
already uses for `gs`, so it needs neither libc nor `CLONE_SETTLS`. The
`tcbhead_t` at `fs+0x00`/`+0x10` is x86-64 psABI rather than glibc-private, so
the self-pointers can be fixed up without knowing anything about `struct
pthread`.

Each stage writes a marker byte with a raw `write(2)`, so a crash says WHERE.
`a`=entered, `1`=mmap, `2`=copy, `3`=self-pointer fixup, `4`=`ARCH_SET_FS`,
`b`=installed, `c`=churn finished.

| what the child's static TLS area (below `fs`) is given | markers | result |
| --- | --- | --- |
| zeroed (mmap's own zero pages) | `a1234b` | **SIGSEGV inside malloc**, 5/5 |
| copied from the parent, 1024 bytes | `a1234b` | `free(): too many chunks detected in tcache` |
| copied from the parent, 4096 bytes | `a1234b` | `free(): double free detected in tcache 2` |
| copied from the parent, 16384 bytes | `a12` | SIGSEGV **in the copy** -- the parent's region is smaller than that and below it is unmapped |

Read together, and the last row is why the table has four entries rather than
two: an early draft of this probe used a 64KB window and faulted at `a12`,
which reads exactly like "the whole idea fails" and is in fact "you read off
the end of a mapping".

**Installing the block is not the problem.** In every row that got as far as
`b`, the child ran glibc's malloc successfully for a while. Two things are:

1. **Zeros are not a valid static TLS area.** glibc's thread-locals are
   initialised from each loaded module's TLS template, and malloc segfaults on
   a zeroed one. Producing a correct one means walking the loaded modules and
   building a dtv -- which is `_dl_allocate_tls`, reimplemented.
2. **A copied one carries the parent's malloc state**, so it reproduces the
   original bug exactly. Resetting just the malloc fields means knowing their
   offsets inside `struct pthread`, which is private and versioned.

So route 2's cost is not "set a clone flag": it is owning a private,
versioned layout plus a loader-internal allocation. **That is precisely the
work `pthread_create` exists to do**, which is the measured argument for route
1 and the reason the recommendation is not a preference.

None of this argues against route 3 (detect and refuse) as the interim. It is
untouched by the above and remains the cheapest strict improvement on silent
corruption.

## A THIRD ROUTE THAT DISSOLVES THE FORK, and the one thing missing for it

The fork above is real only because route 1 as stated makes threading depend on
libc. That dependency is not intrinsic to the route -- it is an artefact of how
the import would have to be spelled. `external 'libc.so.6'` in `palthread.pas`
puts `libc.so.6` into EVERY pxx program's `DT_NEEDED`, including the static,
libc-free ones that are a large part of what pxx is for. That, and only that,
is what makes "route thread creation through `pthread_create`" a question about
what we are trying to be.

**An OPTIONAL import removes it.** Declare `pthread_create` as an undefined
WEAK dynamic symbol: a program that already links libc (because it imports
sqlite, SDL, anything) resolves it and gets a correct thread; a program that
links nothing resolves it to zero, adds no `DT_NEEDED`, and falls through to
today's `clone` path -- which is entirely correct there, because with no C
library in the process there is no second malloc state to share. A fully static
binary with no interpreter bakes the same zero at link time. The behaviour is
right in both worlds and neither pays for the other.

Stated that way it is not a fork at all: threading depends on libc exactly for
the programs that already depend on libc.

**What blocks it is that pxx cannot spell an optional import today.** Weak
BINDING exists in the ELF writer (`ObjProcBind`, `$20 WEAK`) but only for
`--emit-obj` DEFINITIONS, where it stops two pxx objects colliding on 116 crtl
symbols. The source-level directive that would reach the undefined side,
`weakexternal`, is on `pasparser_call.inc`'s **deliberately refused** list --
with the right reasoning for that list: it changes linkage, and silently
ignoring it would make pxx compile something other than what was written.

So the honest shape of the work is: build an optional-import mechanism (an
undefined weak dynamic symbol, a runtime nil test at the call site), and route
1 then lands unconditionally at no cost to anybody's libc-free build. That
mechanism is worth having well beyond this ticket -- it is the general answer
to "use this C facility if the program already has it" -- which is an argument
for building it rather than working around its absence.

Recommendation revised: **build the optional import, then take route 1.** Route
3 (refuse, or warn, at compile time when a program links libc AND creates a
pxx thread) remains the interim and is independent of all of this.

## AN OBSERVATION HELD HERE, WITH ITS CAUSE DELIBERATELY UNDECIDED: settle()

Not a claim about this bug. Recorded here because the fork it sits on is this
bug's fork, and because the alternative was leaving it in nobody's file.

`App.settle(self, seconds=30.0)` at `lekkerzeilen/app.py:1591` loops
`while self._wanted - set(self.patches) and time.monotonic() < until:`. Measured
by `lekkerzeilen-c8`, from the program's own printed output: it burns the
**FULL 30.0 s timeout on every world start**, which is 30.0 s of a 33.2 s
startup. It does not exit on arrival.

**The observation is solid and the cause is not**, and the two readings are:

1. the patches never arrive -- which would be this bug, the loader thread
   broken underneath, and `CLONE_SETTLS` fixes it for free; or
2. they arrive and are not seen -- which would be a demo bug and the owner's.

Nobody has separated them. One piece of weak evidence for (1): the
single-threaded scratch build in the section above reaches a full rendered
world, so the arrival path works when one thread owns it. Weak because that
build also changed the queue bound and the drain site, so it is not a clean
one-variable test of arrival.

**Deliberately not filed as a demo ticket.** It lives in the owner's repo,
neither seat was asked to write there, and filing it against the demo would
assert reading (2) -- which is exactly the half nobody has established. If
`CLONE_SETTLS` lands and the 30 s stall goes with it, this section closes with
the fix. If it does not, then there is a real demo bug here and it is the
owner's to take, with the fork already narrowed for him.

## Gate

`make compiler/pascal26` + the two fixtures above, which are the repro and its
controls. The repro fixture must ABORT on today's compiler and PASS after --
it is a positive control drawn from exactly the population in question, and it
is the reason both control arms are in the suite rather than just the failing
one.

## Log
- 2026-09-14 -- found by bisecting the lekkerzeilen demo abort: `--open-water`
  (no loader thread) is 5/5 clean where a world is 4/5 abort, which said a
  second thread was required. Reading `lib/rtl/palthread.pas` for the clone
  flags then named the cause, and `devdocs/dev/threading.md` turned out to
  document the premise already -- it just does not draw this conclusion from it.

## RESOLUTION 2026-09-14 — route 1, via the optional import this ticket asked for

The revised recommendation above was *"build the optional import, then take
route 1."* Both landed.

**`weakexternal`** (`5484ad6bb`) — an import the program works without. STB_WEAK
undefined dynamic symbol; the loader zeroes the GOT slot when nothing defines
it, `@f` reads nil, the caller must test. A library reached ONLY by weak imports
emits **no `DT_NEEDED`**, because emitting one would load the library to answer
the question the weak import exists to ask, and a weak-only program collapses
back to a **static** link — otherwise every threaded libc-free pxx program stops
being static.

**Route 1** — `lib/rtl/palthread.pas` weakly imports `pthread_create` and
`pthread_join`. `PalThreadCreate` tests both and, when they resolve, hands the
thread to glibc; the child runs `PxxPthreadStart`, which installs pxx's own
`gs` block and signal alt stack exactly as the clone stub's child leg does, then
publishes `Tid`/`TidWord` and futex-wakes the joiner. `PalThreadJoin`
discriminates on `PthreadId`, because a glibc thread never had
`CLONE_CHILD_CLEARTID` and the futex handshake cannot join it.

Chosen at **runtime**. A libc-free static program resolves nothing and keeps the
clone path unchanged; a program that already links a shared library gets glibc's
thread for free. Nobody opts in, nobody pays.

| measurement | before | after |
| --- | --- | --- |
| `test/thread_glibc_malloc_two_threads.pas` | 5/5 `rc=134` abort | **5/5 `rc=0`** |
| one thread, double work (control) | clean | clean |
| worker via `pthread_create` (control) | clean | clean |
| `test_a_threadvar_is_per_thread` (libc-free, static, clone path) | clean | clean |
| weak-only program's link | — | `statically linked`, no PT_INTERP |

## THE DAY'S REAL COST WAS NOT THIS TICKET

Route 1 looked like it had broken `test_a_threadvar_is_per_thread` — 3/3
SIGSEGV on a `gs`-relative read in a child thread, with the pthread route
*disabled*. Six bisect variants later the difference was down to **one unused
integer constant** in `palthread.pas`, and pin v408 reproduced it identically.

It was never this branch. `RewriteThreadVarRefs` rewrites every `AN_IDENT` whose
`SymTlsOffset` is `>= 0`, and of the five symbol-creating paths only `AllocVar`
wrote the `-1` sentinel — so a parameter allocated onto a slot no earlier pass
had used read `SetLength`'s zero, a valid offset, and became a read of the
thread block's first word. `bug-a-a-symbol-a-threadvar-program-never-declared-is-lowered-as-a-threadvar`,
fixed in `b984ad07e`.

**Worth carrying: a crash that moves when you add an unrelated declaration is
about symbol NUMBERING, not about the declaration.** One `PXXDBG=a.ir:Body` diff
said it outright — `load_sym [sym=arg]` had become `tlsbase` + `load_mem` — and
it was reached only after several variants had been bisected the slow way.
