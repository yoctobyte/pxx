---
slug: feature-n-the-queue-module
track: N
prio: 45
type: feature
status: backlog
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, stdlib, mimic, lekkerzeilen, threads]
blocked-by: []
summary: "`import queue` fails with `no unit named queue and no shim mimic_queue`. Measured 2026-09-09 at compiler 418064fca1d3: it is the first wall in lekkerzeilen's `gauges` and `app`. Measured surface is small -- Queue(), Queue(maxsize=N), .put, .get, .get_nowait and the queue.Empty exception -- and the storage is now free: pylib's TPyDeque landed 2026-09-09 and is exactly the right backing structure. THE OPEN QUESTION IS NOT THE CONTAINER, IT IS THE BLOCKING SEMANTICS: CPython's Queue is a THREAD-SAFE blocking queue and both callers use it to hand work between threads, with `except queue.Empty` around a non-blocking get. A single-threaded shim that never blocks is correct for the get_nowait path and WRONG (a deadlock or a silent drop) for a blocking get, so the subset has to be chosen deliberately rather than by writing the easy half. Rank reflects that it is a design question with a small implementation, not a large implementation."
---

# The queue module

## Measured surface (lekkerzeilen, 2026-09-09)

```python
self._landed = queue.Queue()          # gauges.py:370
except queue.Empty:                   # gauges.py:413, app.py:1008
self._orders = queue.Queue()          # app.py:494
self._ready = queue.Queue(maxsize=2)  # app.py:500
```

Constructor with and without `maxsize`, put/get, and the `Empty` exception used
as a control-flow signal around a non-blocking get.

## The container is already there

`TPyDeque` (compiler/builtin/pylib.pas, landed 2026-09-09 for
`collections.deque`) is a double-ended queue with O(1) amortised `popleft`. A
Queue is that plus a capacity bound plus a blocking policy; none of the storage
work needs doing twice.

## The part that needs a decision before code

CPython's `queue.Queue` exists to move objects **between threads**: `get()`
blocks until an item arrives, `put()` blocks when a bounded queue is full, and
`Empty`/`Full` are what the non-blocking variants raise instead of blocking.

Both callers here are genuinely threaded — a producer thread hands work to the
render loop. So:

- `get_nowait()` / `get(block=False)` -> raise `Empty` when empty. Unambiguous,
  and it is what both `except queue.Empty:` sites are catching.
- `get()` with no arguments -> **this is the question.** Returning immediately
  with None would be a silent wrong value; raising would be a divergence from
  CPython on the most ordinary call; a real blocking wait needs the thread
  primitives to be there and correct.

`maxsize` has the mirror question on `put`.

**Do not write the easy half and leave the blocking half to be discovered at
run time.** Either implement the blocking semantics against `lib/rtl/palthread`,
or ship the non-blocking subset with `get()` REFUSED at compile time so the gap
is loud. The second is a legitimate shim (`mimic_codecs` refuses whole classes
of input the same way) and is probably the right first step.
