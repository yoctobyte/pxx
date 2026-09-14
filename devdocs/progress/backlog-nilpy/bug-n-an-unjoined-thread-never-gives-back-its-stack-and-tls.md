---
type: bug
track: N
prio: 75
status: open
slug: bug-n-an-unjoined-thread-never-gives-back-its-stack-and-tls
---

# An unjoined thread never gives back its stack and TLS — 2 mappings and ~1 MB of address space each, forever

`pthread_detach` does not appear ANYWHERE in this tree. A thread created through
`c_pthread_create` and never explicitly `Join`ed is therefore neither joined nor
detached, and glibc is required to keep its stack and TLS for the life of the
process.

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

Default `vm.max_map_count` is 65530. At 2 mappings per thread that is ~32,700
unjoined threads before **every** `mmap` in the process starts failing --
including the heap's own. Not a slope, a cliff, and the failure lands nowhere
near the thread code.

lekkerzeilen creates ~230 threads in 36 s of running (measured by
lekkerzeilen-c8 via gdb thread ids, ~6.4/s, with a live count of only 12-13 --
so almost all of them exit and are never joined). That is roughly **85 minutes**
to exhaust the table. It is invisible to every arena/RSS number taken on that
demo all night, which is the second reason this is worth a ticket: the
instrument in use cannot see the quantity that is growing.

## WHAT THE FIX IS NOT

Do NOT make `PxxPthreadStart` detach itself at exit. A later `Join` on a
detached thread is undefined behaviour, and `Join` is a public API here.

Ownership has to decide. Two candidates, neither implemented:

1. ~~**Detach daemon threads at creation.**~~ **WRONG, CORRECTED 2026-09-15 an
   hour after this ticket was filed.** The original text here said a daemon is
   never joined BY DEFINITION, quoted the registry's *"being killed at exit is
   what daemon MEANS"*, and called it *"unambiguous and cannot race a Join that
   is not allowed to happen"*. **CPython allows `t.join()` on a daemon thread.**
   The registry comment is about what happens at EXIT, not about whether a
   caller may join one, and I read the second into the first. `Thread.join`'s
   blocking arm calls `PalThreadJoin` -> `pthread_join`, so detaching at
   creation turns an ordinary, legal `daemon_thread.join()` into undefined
   behaviour. Do not do this.

   This matters more than a stray sentence because it is where the volume is:
   **all four thread sites in lekkerzeilen pass `daemon=True`** (gauges.py:435,
   app.py:835, app.py:1251, app.py:2520), so the whole ~6.4 threads/s is daemon
   threads and this was going to look like the obvious fix.

2. **Detach on exit, and make `Join` not call `pthread_join` for a detached
   thread.** This is the design that survives the objection above. `Join`'s
   TIMED arm already does the right thing and shows the shape: it waits on
   `TidWord` -- the kernel's own liveness bit, cleared by CLONE_CHILD_CLEARTID
   -- and only then reaps. So:

   * mark the handle detached, detach, and let the thread's resources go at exit
   * `Join` on a detached handle waits on `TidWord` to reach 0 and returns
     WITHOUT `pthread_join`

   That gives Python's semantics (a daemon may be joined; join returns when the
   thread is done) with no leak and no UB. It needs a flag in the handle and a
   branch in both `Join` arms.

3. **Detach a non-daemon thread when its handle is released without a join.**
   Needs a real answer to "who owns the handle", which the Python-level `Thread`
   object has and the RTL does not.

**NOT ATTEMPTED IN THE SESSION THAT FILED THIS, DELIBERATELY.** Option 2 is a
new liveness contract in the most dangerous subsystem in the tree, written at
the end of a long night that had already produced one compiler change passing
all 963 Track N fixtures and killing the demo in 3.0 s of frame loop. Whoever
takes it: gate it on the two NilPy threading fixtures, on `gate.sh quick`, AND
on a built lekkerzeilen -- the fixtures did not catch that one and the demo did,
in three seconds.

Check `lib/rtl/palpthread.pas` and `lib/crtl/src/pthread.c` too -- the C-side
`pthread_join` shim routes through `__pxx_pthread_join`, and whether the C
surface has the same gap is not established here.

## HOW TO MEASURE IT

Count `/proc/self/maps` lines and `statm` field 0 (VSZ), NOT field 1 (RSS).
A probe that watches RSS reports a nearly-flat line for a leak that is
consuming the mapping table at 2 slots per thread. Probe is at
`$SCRATCH/thleak.npy`; the shape is 50 threads spawned-and-joined, then 50
spawned and not joined, with both counters printed between phases.

## RELATED, ALREADY FIXED

The `TidWord` half of this — a TIMED join burning its whole timeout and never
reaping, so `pthread_join` never ran at all — was fixed in `06e40fb95`. That
made timed joins reap; it does nothing for a thread nobody joins.
