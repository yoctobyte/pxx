---
summary: "syncobjs.TCriticalSection had empty method bodies and a TryEnter that always returned True, so threaded code locked with nothing and lost updates silently — 4 threads x 2000 guarded increments summed to 7403, not 8000"
type: bug
track: B
prio: 70
commit: 503f1e94b
---

# `TCriticalSection` was a no-op stub

- **Type:** bug — Track B (`lib/rtl/syncobjs.pas`)
- **Status:** **done** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, case `thread-critical-section`.

It could only be found once something else was fixed: the case frees its
workers with `t[k].Free`, which did not compile until
[[bug-p-free-and-destroy-only-work-on-a-simple-variable]] landed the same
night. Until then the case reported a compile failure and the lock was never
exercised. **A `[known]` tag can hide a second, worse bug behind the first.**

## Repro

Four threads, 2000 increments each, every one inside `Lock.Acquire` /
`Lock.Release`:

| | output |
| --- | --- |
| FPC | `8000` |
| pxx (before) | **`7403`** — and a different number each run |
| pxx (after) | `8000` |

## What it was

Every method was an empty body and `TryEnter` returned `True` unconditionally:

```pascal
procedure TCriticalSection.Acquire;
begin
end;
```

The header explained itself — *"Minimal single-threaded stand-in... give the
methods real bodies when a thread runtime lands."* The thread runtime **did**
land (palthread / palsync / palthreadobj) and this was never revisited. The
stub then stopped being a placeholder and became a silent-corruption bug: code
that correctly guards its shared state gets no exclusion and no diagnostic.

## The fix, and the constraint that shaped it

A test-and-test-and-set spinlock on `__pxxatomic_cas`, plus a `Create` that
zeroes the lock word.

It is **not** `palsync`'s futex `TMutex`, and that is the interesting part:
`palsync uses palthread`, `palthread` contains `__pxxclone`, so reaching it
fails to compile without `--threadsafe`. `uses syncobjs` must not start
demanding that flag — Synapse's `ssfpc.inc` is exactly the caller that would
break, and it does no threading. The atomic intrinsics are compiler builtins
and need no unit, so the lock as written adds no dependency at all.

The cost is stated in the unit header: uncontended Acquire is one CAS like any
mutex; a contended waiter spins instead of sleeping. A performance property,
not a correctness one, and strictly better than no lock.
[[bug-b-futex-helpers-are-trapped-behind-pxxclone]] is the follow-up that would
make it a real blocking mutex — `FLock` is already the futex-word shape, so
that becomes a body-only change.

Not recursive, matching FPC (its `TCriticalSection` initialises a default
pthread mutex, non-recursive on glibc). Detecting re-entry needs an owner
thread id, which needs `gettid`, which is behind the same wall.

## Verification

- `thread-critical-section` matches FPC (`8000`); `thread-interlocked-counter`
  was already correct via `palatomic`, which is what said the atomics were fine
  and the lock was not.
- `TryEnter` is False while held, True when free, and False again immediately
  after taking it.
- `tools/gate.sh lib` GREEN, `tools/gate.sh quick` GREEN, 34/34 demos.
