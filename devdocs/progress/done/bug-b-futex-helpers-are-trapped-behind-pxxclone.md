---
summary: "PalFutexWait/Wake live in palthread next to __pxxclone, so any unit wanting a blocking lock inherits the --threadsafe compile gate; that forced syncobjs' TCriticalSection to be a spinlock and palatomic to be a separate unit"
type: bug
track: B
prio: 35
owner: claude-B
---

# The futex helpers are trapped behind `__pxxclone`

- **Type:** bug (structural) — Track B (`lib/rtl`)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** implementing `TCriticalSection` for real
  ([[bug-b-criticalsection-was-a-no-op-stub]]) and, before that,
  `lib/rtl/palatomic.pas`.

## The shape

`PalFutexWait`, `PalFutexWaitTimeout` and `PalFutexWake` are three-line
`__pxxrawsyscall(SYS_futex, ...)` wrappers. They live in `lib/rtl/palthread.pas`
— which also contains `__pxxclone`. Reaching that unit at all fails the compile:

```
error: __pxxclone (thread creation) requires --threadsafe or {$threadsafe on}:
the default heap/ARC/console-I/O runtime is not thread-safe
```

That gate is right for thread *creation*. It is wrong for *waiting on a word*,
which needs no thread-safe heap and no threads at all to compile.

## What it has already cost

- **`syncobjs.TCriticalSection` is a spinlock, not a blocking mutex.** It cannot
  use `palsync`'s futex `TMutex` because `palsync uses palthread`, and
  `uses syncobjs` must not start requiring `--threadsafe` — Synapse's
  `ssfpc.inc` is exactly the caller that would break, and it does no threading.
  So a contended waiter burns CPU instead of sleeping.
- **`palatomic` had to be its own unit** rather than living in `palsync` with
  the other users of the same intrinsics, for the identical reason: an
  `InterLockedIncrement` on a refcount must not drag in thread creation.

## The fix

Move the three futex wrappers (plus the `SYS_futex`/`FUTEX_WAIT`/`FUTEX_WAKE`
constants and whatever per-arch `{$ifdef}` block they need) into a new
dependency-free `lib/rtl/palfutex.pas`, the way `palatomic` is dependency-free.
Then:

- `palthread` uses `palfutex` (its own callers keep working, but note Pascal
  `uses` is not transitive — every caller of `PalFutexWait` needs its own
  `uses palfutex`);
- `palsync` uses `palfutex` instead of `palthread` — check whether it needs
  anything else from there first;
- `syncobjs` can then use `palsync` and `TCriticalSection` becomes a real
  blocking mutex, a body-only change (`FLock` is already the futex-word shape).

Current `PalFutex*` callers: `palthread`, `palthreadobj`, `palpthread`,
`palsync`, `palparallel`.

## Gate

Track B: `tools/gate.sh lib`. Also rebuild the threading demos and re-run
`tools/fpc_diff_probe.sh`'s `thread-*` cases — `thread-critical-section` is the
one that proves the lock still excludes.

## Log
- 2026-08-09 — resolved, commit 59104b815.
