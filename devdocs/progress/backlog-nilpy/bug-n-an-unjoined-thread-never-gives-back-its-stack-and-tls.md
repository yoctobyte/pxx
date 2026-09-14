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

1. **Detach daemon threads at creation.** A daemon is never joined BY
   DEFINITION -- `mimic_threading.pas` says so in its own registry comment:
   *"being killed at exit is what daemon MEANS"* -- so detaching one at
   `pthread_create` time is unambiguous and cannot race a `Join` that is not
   allowed to happen. This is the safe half and is probably most of the volume.
2. **Detach a non-daemon thread when its handle is released without a join.**
   Needs a real answer to "who owns the handle", which the Python-level `Thread`
   object has and the RTL does not.

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
