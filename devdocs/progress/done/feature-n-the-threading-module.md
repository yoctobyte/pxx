---
slug: feature-n-the-threading-module
track: N
prio: 60
type: feature
status: done
owner: "frankB"
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, mimic, lekkerzeilen, threads, palthread]
blocked-by: []
summary: "DONE 2026-09-10 (frankB), landed with the mimic_queue work in ONE commit because neither is safe alone. `import threading` resolves to lib/rtl/mimic_threading.pas over the RTL's clone-based PAL (palthread/palfutex/palsync, all unchanged) -- a binding job, as the ticket said. Thread(target=, args=, daemon=, name=) with .start()/.join(timeout=)/.is_alive(), Event with .set()/.clear()/.is_set()/.wait(timeout)->flag, and Lock. mimic_queue's blocking arms are real condvar waits now and the class has a mutex. `daemon=True` MEASURED FREE: an unjoined thread does not keep the process alive (exit_group), which is exactly CPython's semantics; the NON-daemon thread is the one that needed work and is joined in finalization. The old refusal's DIAGNOSIS is kept via pythreadlive.pas -- a wait nothing can satisfy still raises rather than hanging, which is a deliberate divergence recorded in nilpy-semantics-divergences.md. --threadsafe is still REQUIRED (the lock defines are applied before lexing, so {$threadsafe on} is refused by the lexer itself); a NilPy-level diagnostic now names the flag, and implying it is feature-n-import-threading-should-imply-threadsafe."
---

# The threading module

`import threading` reaches no unit and no shim.

## Why it is the one left

Measured 2026-09-10, compiler `61f8a78f8aae`, per-import:

| import | app.py | gauges.py | resolves? |
| --- | --- | --- | --- |
| array, math, os, json, sys, time | ✓ | ✓ | yes |
| sqlite3 | ✓ | ✓ | yes |
| urllib.request / urllib.error | — | ✓ | yes (shim) |
| queue | ✓ | ✓ | **yes, as of today** |
| **threading** | ✓ | ✓ | **NO** |

So this is the last import-level wall in both. It is not measured as *sufficient*
for either module — nothing here says the module bodies compile once the imports
do, and the honest claim is first-wall only.

## Measured surface (lekkerzeilen, 2026-09-10)

```python
self._thread = threading.Thread(target=self._loader, daemon=True, ...)  # app.py:751, 1165
self._chart_worker = threading.Thread(...)                              # app.py:1778
self._thread = threading.Thread(target=self._run, daemon=True, ...)     # gauges.py:435
self._thread.start()                                                    # app.py:1167, 1780
self._thread.join(timeout=2.0)                                          # app.py:1071, 1105

self._stop = threading.Event()                                          # gauges.py:402
self._stop.set()                                                        # gauges.py:455
while not self._stop.is_set():                                          # gauges.py:477
if self._stop.wait(self.period):                                        # gauges.py:482
```

Four Thread constructions, `.start()`, `.join(timeout=)`, and one Event with
`set` / `is_set` / `wait(timeout)`. No Lock, no Condition, no Semaphore, no
`current_thread()`, no thread-local. `Event.wait(timeout)` returning the flag is
load-bearing — gauges.py uses it as its poll interval, so a `wait` that ignored
the timeout would spin.

## The runtime already exists

`lib/rtl/palthread.pas` exports `PalThreadCreate(var h; entry; arg; ...)`,
`PalThreadJoin`, `PalThreadSelf`, `PalThreadExit` — clone-based, with a TLS carve
(4224 bytes as of `7a166c995`) and PAL_MIN_STACK at 128 KiB. So the work is
binding a Python-shaped API onto an existing threading runtime, not building one.

`daemon=True` is the interesting parameter: every Thread in the corpus sets it,
and it means "do not keep the process alive". Whether that is free or needs
bookkeeping at exit depends on what `PalThreadCreate` leaves behind, and that is
the one thing to measure before estimating this.

## What must change in mimic_queue AT THE SAME TIME

Both are in `lib/rtl/mimic_queue.pas`'s header, and neither is safe alone:

1. **`WouldBlock` becomes a real wait.** Today a blocking `get()` on an empty
   queue raises with a message saying no other thread can satisfy it — correct
   while that is true, and wrong the moment it stops being true. One call site
   for each of get and put, deliberately funnelled through one function so there
   is one place to change rather than two to find.
2. **The class must gain a lock.** There is none today, on purpose: with one
   thread a lock is pure cost, and a lock that is never contended is never
   tested. Landing threading without landing the mutex makes the one class whose
   entire purpose is cross-thread hand-off into a data race.

`app.py`'s `_ready` queue is `maxsize=2`, so its `put` really does block in
CPython, from a loader thread, while the render loop drains with `get_nowait`.
That is the exact shape both changes exist for.


## SURFACE ADDENDUM — frankZ, 2026-09-10, measured at compiler 69c84acb1501

Two corrections to the numbers above, neither changing the ranking.

**`name=` is used at every Thread construction site and was not in the surface
list.** All four:

    gauges.py:436   name="gauges"
    app.py:785      name="lz-tiles"
    app.py:1201     name="lz-tiles"
    app.py:2284     name="lz-chart"

A shim implementing `Thread(target=, daemon=, args=)` and nothing else refuses
**100% of the corpus's call sites** while looking complete against the surface
as previously written. This is the collide-with-the-default shape one level up:
the omission is invisible until the shim exists, and then it fails everywhere
at once rather than in the one place a spot-check would look.

**It is TWO modules with real threading sites, not three.** The census reports
`__main__.py` walled on `no unit named threading` at `:36`, and **`__main__.py`
contains no threading reference at all** — `:36` is a blank line there. It is a
cascade through `import app`. So:

    gauges.py   REAL   threading.Event(), threading.Thread(...)
    app.py      REAL   threading.Thread(...) x3
    __main__.py CASCADE — zero threading references

That is the fifth same-line-number cascade confirmed in this corpus and it is
already recorded in the census baseline. It does not lower the value — clearing
threading still moves three modules, and two of the three are the app's own
entry points — but **the WORK is two files' worth of call sites, not three**,
and a reader ranking on the census row count would size it wrong.

The full object surface, for completeness: `Thread` with `.start()` and
`.join()`; `Event` with `.set()`, `.wait()`, `.is_set()`. Two classes, five
methods, four kwargs. Every one of the four Thread uses is a `daemon=True`
background worker with a `target=`, so the semantics actually needed are narrow
— no thread returns a value, none is re-joined after timeout, none subclasses
Thread.

**Not started.** It is a two-part job by the ticket's own account — the
`mimic_queue` blocking-wait and lock work must land with it — and half a door
is worse than none. Left ranked and unowned.

## RESOLVED 2026-09-10 (frankB) — `176b91802`

Landed with the `mimic_queue` half in ONE commit, per this ticket's own
requirement. Compiler `ccdbbcacb631`.

### What the corpus surface turned out to be, and the lesson in it

frankZ's `name=` correction above was the load-bearing one and it generalises:
**an API surface is what a module OFFERS; a corpus surface is what the corpus
ASKS FOR, and only the second is a specification for a shim.** The original
surface here was read off `threading.Thread`'s documented signature and missed
a kwarg that all four call sites pass — a shim built to it would have refused
100% of them while looking complete. Re-measured from the call sites, the whole
corpus surface is:

    threading.Thread(target=, daemon=, name=)          x3
    threading.Thread(target=, args=, daemon=, name=)    x1
    threading.Event()                                   x1
    .start()  .join(timeout=)  .set()  .is_set()  .wait(<float>)

All four targets are BOUND METHODS; one site passes a 2-tuple.

### The two things the ticket said must land together, both landed

`WouldBlock` is a real wait on two condition variables — a `get` waiter and a
`put` waiter are waiting for opposite events, and one condvar wakes the wrong
sleepers, which with `maxsize=2` is the common case. The class has a mutex.

### `daemon=True` is FREE — the one thing this ticket said to measure first

Measured, not assumed: a program that spawns a thread and returns from main
without joining exits immediately with rc=0, and the child's output never
appears. The teardown is `exit_group`, which takes every thread with it —
precisely CPython's daemon semantics. **The NON-daemon thread is the one that
needed work**, since killing it mid-flight loses whatever it was doing with no
diagnostic; those are registered and joined in `finalization`.

### The diagnosis is not lost, and that is a deliberate divergence

Blocking correctly would have thrown away the old refusal's message for every
single-threaded program. `pythreadlive.PyThreadLiveAny` — one integer in a unit
of its own — lets the wait ask whether anything could ever satisfy it, and the
old text is raised verbatim when nothing can. Asked INSIDE the wait loop, not
once before it: a queue can have a feeder when the wait begins and lose it.
`devdocs/dev/nilpy-semantics-divergences.md` carries the argument.

### What did NOT get done, and it is a real gap

`--threadsafe` is still required on the command line. It cannot be implied by
the shim: the lock-implementation defines (`PXX_TS_HARDLOCK`/`PXX_TS_SOFTLOCK`)
are applied BEFORE lexing, and the lexer refuses `{$threadsafe on}` saying so
in its own message. Implying it has to happen at option time from a pre-scan of
the source, which is `feature-n-import-threading-should-imply-threadsafe`. A
NilPy-level diagnostic now names the flag at the import, so the failure no
longer points at `lib/rtl/palthread.pas` three units down.

### Effect on lekkerzeilen, measured with --threadsafe

The threading wall is CLEARED on all three modules that carried it.

    gauges.py    :141  urllib.request.Request(url, headers=...) — a keyword
                       argument to a stdlib dotted call, which is
                       bug-n-a-stdlib-dotted-call-cannot-take-a-keyword-argument
    __main__.py  :141  the SAME number, and that line is PROSE there — the
                       sixth same-line-number cascade in this corpus
    app.py       :10   ctypes

So the next wall on this path is a ticket that already exists and is one fix,
not three.
