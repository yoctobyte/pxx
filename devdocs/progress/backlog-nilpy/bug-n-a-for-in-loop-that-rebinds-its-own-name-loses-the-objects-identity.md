---
type: bug
track: N
prio: 65
status: open
slug: bug-n-a-for-in-loop-that-rebinds-its-own-name-loses-the-objects-identity
---

# `for t in ts:` where `t` already holds one of the elements loses that object's identity

Isolated 2026-09-15 to a ONE-CHARACTER difference. Both programs start and join
300 threads; only the loop variable's NAME differs.

```python
import threading
def body(): return 0
for r in range(300):
    ts = []
    t = threading.Thread(target=body)
    t.start()
    ts.append(t)
    for t in ts:        # <- rebinds the name that already holds this object
        t.join()
```

| loop variable | spurious `more than 64 unjoined non-daemon threads` on stderr |
|---|---|
| `for t in ts:` | **236** of 300 |
| `for u in ts:` | **0** |

236 is exactly 300 - 64: the registry fills once and then never drains, so
every subsequent `Thread.start` reports an overflow that has not happened.

## WHAT IT MEANS, AND IT IS NOT ONLY NOISE

`mimic_threading.LiveRemove` finds its entry by identity (`gLive[i] = t`) and
is called from `Thread.join`. When the name is rebound, that comparison stops
matching, so:

- the registry keeps corpses and reports an overflow that is not real -- a
  diagnostic that exists to flag a genuine leak becomes noise that would hide
  one, which is the exact failure `LiveRemove` was written to fix;
- the exit-time join list is wrong, so a non-daemon thread past the full
  registry is not joined at exit.

The join itself still WORKS -- the program completes and `FJoined` sticks -- so
whatever the loop variable ends up holding still reaches the same instance
through the method call. That is the interesting part and it is not yet
explained: the object is reachable enough to `join` and not equal enough to
find. Do not assume a freed box until that is measured.

## WHY IT WAS NOT FOUND BY THE CONTROL THAT SHIPPED WITH LiveRemove

`mimic_threading.pas` records the control as *"100 threads started and joined
in a loop"* -- `t.start(); t.join()` with no list. That arrangement joins the
element that was added LAST, every time, so a swap-with-last removal succeeds
by position whatever the comparison does, and the rebinding never happens.
Measured here: that exact shape prints **0** warnings on the broken build.

This is `normalise-dont-special-case.md`'s ordered-list rule in a second
subsystem -- *the passing arrangements are not a sample, they are the
population everyone writes* -- and `for t in ts:` after `ts.append(t)` is an
extremely ordinary thing to write.

## NEXT STEP

`PXXDBG=a.ir` on the two spellings and diff them; the question is what the
for-in store does differently when the destination already holds the payload
it is about to be given. The aliasing case is already known to the variant copy
arm (`bug-a-a-variant-assigned-to-itself-becomes-empty` is the same shape from
the assignment side), so look there first.

Found while building the fixture for
`bug-n-a-blocking-get-raises-while-a-thread-is-alive`; the two are unrelated
defects that met in one file.
