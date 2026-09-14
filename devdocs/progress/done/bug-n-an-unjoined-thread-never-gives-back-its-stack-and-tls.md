---
type: bug
track: N
prio: 75
status: done
slug: bug-n-an-unjoined-thread-never-gives-back-its-stack-and-tls
---

# A thread nobody joins never gives back its 1028 kB stack mapping

**THE MECHANISM IN THE FIRST VERSION OF THIS TICKET WAS WRONG AND IT IS
CORRECTED IN PLACE BELOW.** It said the missing `pthread_detach` was the cause
and that glibc was holding the memory. It is not: pxx programs are statically
linked unless something drags in a shared library, `PthreadRouteAvailable`
answers False, and **the CLONE route is what actually runs**. A `routeprobe`
printed `PthreadId=0`, and `readelf -d` on the fixture binary shows no dynamic
section at all. The leaked memory is OURS, not glibc's: `PalThreadJoin` is the
only thing in the tree that munmaps `h.StackBase`, so a thread nobody joins
keeps its own stack mapping forever. The whole detach design in "WHAT THE FIX
IS NOT" below was built for a route these programs never take.

Measured at the same time: the leak is **one mmap of exactly `h.StackSize`**
(1024 kB stack + a 4 kB guard page), not two resources. It reads as 2 mappings
because `PalThreadCreate` mprotects the low page PROT_NONE, which splits one
VMA into two. 1028 kB per thread accounts for it completely, so there is no
second leaked region to look for — the TLS and alt-stack blocks named in the
old title are carved off the top of that same mapping on this route.

Measured 2026-09-15, `--threadsafe`, CPython as oracle:

| | mappings | VSZ |
|---|---|---|
| pxx, 100 threads started **and joined** | 10 -> 10 | flat |
| pxx, 100 threads started, **never joined** | 10 -> **209** | **+1028 kB per thread** |
| CPython, either way | 50 -> 50 | flat |

Exactly **2 mappings per unjoined thread**, never returned. RSS grows only
~8.6 kB/thread, which is why every RSS-based leak instrument we have is blind to
this: a thread stack is mmap'd and mostly untouched, so it costs ADDRESS SPACE
and mapping-table slots rather than resident pages.

## THE RESOURCE THAT RUNS OUT IS THE MAPPING TABLE, NOT MEMORY

`vm.max_map_count` bounds it: every `mmap` in the process, the heap's own
included, starts failing once the table is full, and the failure lands nowhere
near the thread code. Not a slope, a cliff.

**THE "85 MINUTES TO A CLIFF IN LEKKERZEILEN" IN THE FIRST VERSION OF THIS
TICKET WAS WRONG IN BOTH FACTORS AND THE DEMO DOES NOT HIT THIS AT ALL.**
Recorded here rather than deleted, because the way it was wrong is the reusable
part:

* **The constant was recalled, not read.** I wrote `vm.max_map_count` = 65530,
  the documented default. This box is at **1048576** — sixteen times further
  away — and `/proc/sys/vm/max_map_count` was one `cat` away the whole time.
* **The population was invented from the half of a peer's report I liked.**
  lekkerzeilen-c8 gave me "~230 thread creations in 36 s" from gdb thread ids
  AND a live count of 12-13, and I ran per-thread arithmetic on the first
  without ever asking whether those 230 stacks survive. They do not.

c8's direct measurement of the running demo, sampled every 60 s with a positive
control proving the counter reads non-zero, settles it:

| t_s | maps | VSZ_MB | RSS_MB | threads |
|---|---|---|---|---|
| 0 | 824 | 2684 | 179 | 11 |
| 60 | 859 | 2770 | 321 | 10 |
| 120 | 860 | 3026 | 449 | 10 |
| 300 | 860 | 3538 | 962 | 10 |
| 480 | 860 | 3794 | 1218 | 10 |

**Mappings flat at 860 for six minutes** while RSS climbs a full gigabyte —
that climb is the arena chain, a different defect. So this bug is real on its
own fixture and **lekkerzeilen does not accumulate unjoined-thread mappings**.
It is not a lekkerzeilen blocker and must not be ranked as one. That is also
why it is filed against the LANGUAGE: a server or worker-pool program that
starts threads faster than it joins them is the population that hits it, and we
do not have one to measure.

## WHAT THE FIX IS NOT (kept: it is correct about the pthread route, which is
## not the route in play, and someone will propose it again)

Do NOT make the thread detach itself at exit and do NOT detach daemon threads at
creation. **CPython allows `t.join()` on a daemon thread**, so detaching at
creation turns a legal `daemon_thread.join()` into undefined behaviour. (That
correction was itself a correction to this ticket, made an hour after filing:
the registry's *"being killed at exit is what daemon MEANS"* is about EXIT, not
about whether a caller may join one, and I read the second into the first.)

A `PalThreadDetach` + detached-first arm in `PalThreadJoin` WAS written and
measured on 2026-09-15. It changed nothing — pre-fix and fixed both leaked 120
maps / 61680 kB per 60 threads — because it targets `pthread_detach` on a route
these binaries never take. It was **reverted rather than landed**: it is
plausible-looking, unexercised on this box, and CLAUDE.md's rule is *"Verified,
not believed."* If the pthread route ever becomes the common one, that design is
the right one and this paragraph says where to start.

## WHAT LANDED: A REAPER, BECAUSE A THREAD CANNOT FREE ITS OWN STACK

The release has to happen on another thread, later — which is also how glibc
does it. `lib/rtl/palthread.pas` now keeps a small table of clone-route handles
and sweeps it at the top of every `PalThreadCreate`, munmapping any entry whose
`TidWord` the kernel has cleared.

`TidWord` is the signal and it is the kernel's, not ours: `CLONE_CHILD_CLEARTID`
zeroes it in `mm_release()` during `do_exit`, after the thread can no longer
touch its user stack. `PalThreadJoin` already waits on that exact word before
its own munmap, and `pthread_join` relies on the same guarantee to recycle a
stack.

**Registered at CREATE, not at DETACH, and that is the design decision.** An
explicit detach needs every caller to predict that it will not join;
`daemon=True` is one such caller, but an ordinary thread that is simply never
joined is the same leak with nobody to flag it. Sweeping on the kernel's
liveness bit covers both: a joined thread has `StackBase = 0` by then and is
skipped, and a thread joined LATER finds `StackBase = 0`, its `TidWord` already
0, and returns without waiting.

Two guards worth knowing about before touching it:

* A handle is registered only with the kernel's tid already in `TidWord`
  (`CLONE_PARENT_SETTID` lands before `clone` returns to the parent). A handle
  registered with `TidWord = 0` reads as ALREADY DEAD and the next sweep would
  unmap a RUNNING thread's stack. If that word is not set, or the table is
  full, the handle is simply not registered and its stack leaks exactly as
  before — the one failure mode that cannot make anything worse.
* `PalThreadJoin` no longer does `if StackBase > 0 then munmap`. A Join racing a
  sweep would both see it non-zero and unmap twice, and the second unmap is
  harmless only until that address has been handed back out by another `mmap`.
  `ReapTakeStack` makes the test-and-zero one atomic step.

Bound: a dead thread's stack is held until the next thread starts. The last
thread's stack is never reclaimed — one mapping at exit, not a growing leak.

## THE FIXTURE, AND WHAT ITS CONTROLS ARE FOR

`test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy`, wired into the
test target with `--threadsafe` (without it `mimic_threading` is unreachable and
the row would pass by not testing anything).

| row | pre-fix | fixed | CPython |
|---|---|---|---|
| daemon, 60 threads, nobody joins | +120 maps / +61680 kB | **+0 / +0** | +0 / +0 |
| joined, 40 threads | +0 | +0 | +0 |
| live control, 40 threads still running | +80 maps | +79 | +87 |
| all threads completed | 80/80 | 80/80 | 80/80 |

The `live` row is the positive control and it guards **the dangerous
direction**. Every other row asserts a number stays near zero, so a broken
instrument passes all of them. More than that: the way this fix can be WRONG is
freeing a stack still being stood on, so `live` holds 40 threads open across
further thread creation — every creation sweeps — and asserts both that the
mappings are visible (the instrument moves) and that all 80 threads still
finish with a correct count. Both controls pass on the PRE-FIX build too, which
is what makes the one red row attributable.

Gated on: the fixture against a real pre-fix control (`PXX_HOME` at a
`git archive HEAD` tree), 17 named threading fixtures, `gate.sh quick` GREEN,
and a built lekkerzeilen that survived its full 90 s run (in-loop 86.78 s,
against the known-good 87.17 s) — because tonight already produced a change
that passed all 963 Track N fixtures and killed the demo in 3.0 s.

## HOW TO MEASURE IT

Count `/proc/self/maps` lines and `statm` field 0 (VSZ), NOT field 1 (RSS).
A probe that watches RSS reports a nearly-flat line for a leak that is
consuming the mapping table at 2 slots per thread (one mmap, split by the
guard page). Probe is at
`$SCRATCH/thleak.npy`; the shape is 50 threads spawned-and-joined, then 50
spawned and not joined, with both counters printed between phases.

## RELATED, ALREADY FIXED

The `TidWord` half of this — a TIMED join burning its whole timeout and never
reaping, so `pthread_join` never ran at all — was fixed in `06e40fb95`. That
made timed joins reap; it does nothing for a thread nobody joins.

## Log
- 2026-09-15 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
