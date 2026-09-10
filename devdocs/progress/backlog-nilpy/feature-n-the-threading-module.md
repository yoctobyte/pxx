---
slug: feature-n-the-threading-module
track: N
prio: 60
type: feature
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, mimic, lekkerzeilen, threads, palthread]
blocked-by: []
summary: "`import threading` fails with `no unit named threading and no shim mimic_threading`. Measured 2026-09-10 at compiler 61f8a78f8aae: with mimic_queue landed the same day, threading is now the LAST import-level wall in lekkerzeilen's `app` and `gauges` -- every other import in both files resolves (array, math, os, json, queue, sqlite3, sys, time, urllib.request, urllib.error all measured RESOLVES). The measured surface is four names: Thread(target=, daemon=, args=, NAME=), .start(), .join(timeout=), and Event with .set()/.is_set()/.wait(timeout) -- `name=` added 2026-09-10 by frankZ and it is load-bearing: ALL FOUR Thread construction sites in the corpus pass it, so a shim without it refuses every one of them. NOT a fantasy ticket: pxx already has real clone-based threads at the RTL level -- lib/rtl/palthread.pas exports PalThreadCreate/PalThreadJoin/PalThreadSelf/PalThreadExit -- so this is a binding job, not a runtime one. TWO THINGS MUST LAND TOGETHER: mimic_queue's blocking get()/put() currently RAISE (nothing single-threaded could ever satisfy them) and must become real waits, and mimic_queue has no lock, deliberately, because an uncontended lock is also an untested one. A Queue reachable from two threads with no mutex is a data race in the one class most likely to be used across threads."
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
