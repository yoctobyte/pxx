# `--threadsafe` heap lock: test-and-test-and-set + PAUSE

2026-08-20, plexus (12 cores), `bench/threadsafe_heap_scaling.pas`,
`make benchmark-threadsafe-heap`. Track T's watcher was running throughout, so
the absolute milliseconds are noisy — **the ratios are the result**.

## What is measured

400,000 `GetMem`/`FreeMem` pairs of 128 bytes, **total**, divided among the
threads. Total allocator work is therefore constant and only the concurrency
changes, so:

- flat wall time = perfectly scaling allocator,
- rising = the global lock serialising the work,
- rising *faster than serialisation alone* = waiters interfering with the holder.

## Result (median of 3)

| threads | 1 | 2 | 4 | 8 |
| --- | --- | --- | --- | --- |
| `lock xchg` spin loop (before) | 66 ms | 100 ms | 132 ms | 171 ms |
| TTAS + `pause` (after) | 60 ms | 74 ms | 90 ms | 122 ms |
| improvement | — | −26% | −32% | −29% |

Single-thread cost is **unchanged**: the uncontended path is one atomic either
way, and the 66-vs-60 gap is run-to-run noise, not a win.

## Why it works

A bare `lock xchg` loop performs an atomic read-modify-write on *every* spin,
and each one takes the lock's cache line exclusive — so N waiters bounce a line
that the **holder** also needs in order to finish and release it. The waiters
slow down the very work they are waiting for, which is why the old curve grew
faster than the thread count.

TTAS spins on an ordinary load instead (shared line, no bus traffic) and only
attempts the atomic when the lock looks free. `PAUSE` throttles the loop and
yields the pipeline to a hyperthread sibling.

## What this is NOT

**It does not make the allocator scale.** The lock is still global and exactly
one thread allocates at a time; the remaining rise is honest serialisation. Only
the contention *overhead* — the part that was pure interference — is gone.

Flattening the rest needs per-thread arenas, and that is blocked on the runtime
having no thread-local storage at all: `PXX_CLONE_THREAD` is `$350F00`, which
does **not** include `CLONE_SETTLS`, so every thread shares the parent's `fs`
base. See `feature-a-thread-local-storage-via-clone-settls`.
