---
slug: feature-n-the-queue-module
track: N
prio: 45
type: feature
status: done
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, stdlib, mimic, lekkerzeilen, threads]
blocked-by: []
summary: "RESOLVED 2026-09-10 by lib/rtl/mimic_queue.pas, byte-identical to CPython. THE DESIGN QUESTION THIS TICKET HELD ITSELF OPEN FOR WAS SETTLED BY MEASUREMENT, NOT BY CHOOSING: NilPy has no `threading` at all, and a blocking get() on an empty queue is a deadlock in single-threaded CPython too -- it hangs rather than answering -- so raising there refuses nothing a working program relies on and turns an unobservable hang into a diagnosis. Every arm with a defined answer is implemented exactly, including a SATISFIABLE blocking get()/put(), which is the common case; the one arm with no defined answer refuses through a single WouldBlock() so there is one site to convert. Storage is pylib's TPyDeque, free since 2026-09-09. IT CLEARS NOTHING AND THAT IS THE HONEST NUMBER: behind queue in both app.py and gauges.py sits threading, and every other import in both resolves, so first-wall count 2 and sufficient count 0. The value is that two modules with unknown walls became two modules with ONE named wall -- feature-n-the-threading-module, prio 60, which also names the two things that must land with it (WouldBlock becomes a real wait; this class must gain a lock it deliberately does not have). Found and filed en route: bug-n-a-keyword-argument-does-not-bind-when-a-constructor-overload-set-contains-a-zero-parameter-arm."
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

## RESOLVED 2026-09-10 (frankB) — `lib/rtl/mimic_queue.pas`, and the design question answered by measurement

Byte-identical to CPython across `test/test_nilpy_the_queue_module.npy`.

**The design question this ticket held itself open for is settled, and it was
settled by measuring rather than by choosing.** The ticket said a single-threaded
shim that never blocks is right for `get_nowait` and wrong for a blocking `get`,
and that the subset had to be chosen deliberately. Two measurements decided it:

1. **NilPy has no `threading`** — `import threading` reaches no unit and no
   shim. So today nothing could ever satisfy a wait.
2. **A blocking `get()` on an empty queue is a deadlock in CPython too**, in a
   single-threaded program. It does not return a wrong answer; it hangs. So
   raising is not refusing anything a working program relies on — it turns an
   unobservable hang into a diagnosis, which is what CLAUDE.md asks for where an
   input is only produced by a mistake.

So this is not "the easy half": every arm with a defined answer is implemented
exactly, including a blocking `get()`/`put()` that IS satisfiable — the common
case, and the one app.py:1294 reaches whenever an order is already waiting. The
one arm with no defined answer refuses, loudly, through a single `WouldBlock`
function so there is one site to convert when threading lands.

**`threading` is now filed as its own ticket** (`feature-n-the-threading-module`,
prio 60) and it names the two things that must land WITH it: `WouldBlock` becomes
a real wait, and this class must gain a lock. There is none today on purpose —
an uncontended lock is also an untested one — and landing threading without it
makes the one class whose whole purpose is cross-thread hand-off a data race.

**A compiler defect found by writing it, filed:**
`bug-n-a-keyword-argument-does-not-bind-when-a-constructor-overload-set-contains-a-zero-parameter-arm`.
`queue.Queue(maxsize=2)` — app.py:575 verbatim — refused, while `Queue(2)`
worked and the parameter really was named `maxsize`. Narrowed with three
controls; the first diagnosis ("overloaded constructor") was wrong and
`array.array(tc="h")` refutes it. Worked around by collapsing to one constructor
with a default, marked REVERT TO TWO OVERLOADS — the second shim in two days to
collapse a constructor overload set for a reason that is not about the shim.

### Result on the target: clears NOTHING, and that is the honest number

Behind `queue` in both `app.py` and `gauges.py` sits `threading`. Every other
import in both files resolves — array, math, os, json, sqlite3, sys, time,
urllib.request, urllib.error, all measured — so `queue` was the second-to-last
import wall and neither module compiles until threading lands. **This ticket's
first-wall count is 2 and its sufficient count is 0.**

Worth doing anyway, and the reason is not "it was cheap": it turns two modules
with two unknown walls each into two modules with ONE named wall, which is what
makes `feature-n-the-threading-module` a rankable ticket instead of a guess.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## INERT FOR `$(PXX_STABLE)` CONSUMERS UNTIL THE NEXT PIN — say it here, do not wait for it

`gate.sh quick` is **RED on one row** at this commit, and it is this change:

```
the PINNED binary cannot COMPILE 1 of 56 root units that a compiler built
from THIS TREE compiles cleanly:
  mimic_queue :: pascal26:78: error: unknown type: TPyDeque
```

`self-host fixedpoint` PASSES, which is the row that gates; this one grades.

**Caused by me and not fixed by me, deliberately.** `TPyDeque` is a pylib
builtin that landed 2026-09-09 (my own `d1efd1dee`) and no pin carries it yet.
Reshaping `mimic_queue` onto `TPyList` with an O(n) popleft would turn the
canary green and would be precisely the compiler-appeasement workaround
CLAUDE.md refuses: the platonic code stays, the canary's own message says *"the
change is usually RIGHT and the remedy is a pin, not a revert"*, and `make pin`
is owner-only.

**What is actually inert:** anything that builds `lib/rtl` with `$(PXX_STABLE)`
cannot compile `mimic_queue` until a pin carries `TPyDeque`. NilPy programs are
unaffected — they compile against the live `compiler/pascal26`, which is how the
test row above passes.

Recorded per CLAUDE.md's rule that a fix a `lib/**` file depends on must say
whether a pin carries it. Not waiting for one: a session that stalls on an event
only the owner can cause is indistinguishable from a session that is working.
Existing ticket for the standing condition:
`bug-a-the-pinned-compiler-cannot-build-live-lib-rtl-and-nothing-tracks-it`.
