---
type: bug
track: N
prio: 40
status: open
slug: bug-n-a-for-in-loop-that-rebinds-its-own-name-leaves-the-thread-registry-undrained
---

# `for t in ts:` where `t` already holds one of the elements leaves the thread registry undrained

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

## WHAT IS MEASURED, with probes in LiveAdd and LiveRemove

Four rounds, probe on every add and every remove, printed in order:

```
rebound  (for t)          distinct (for u)
  add   now=1               add   now=1
  add   now=2               hit   now=0
  add   now=3               add   now=1
  add   now=4               hit   now=0
  DONE                      ... x4
  MISS  now=0               DONE
  MISS  now=0
  MISS  now=0
  MISS  now=0
```

`LiveAdd` runs either way. In the rebound spelling **every `LiveRemove` happens
after the program's last statement** — that is the exit-time joiner, which
zeroes the count first by design, so each call is a no-op on an empty registry.
During the program the registry only ever grows.

## WHAT IS NOT ESTABLISHED — RETRACTED FROM THIS TICKET'S FIRST VERSION

It first said `LiveRemove`'s identity comparison stops matching. **That was a
guess written as a finding and the probe does not support it**: the misses land
on an EMPTY registry after exit, which is what a `LiveRemove` that was never
reached during the program looks like, not what a failed comparison looks like.

**And the join itself still WORKS.** Measured with a 0.4 s body and an
append-ordered log, both spellings print `['body', 'after-join']`, matching
CPython — so `join` waits, and this is not a silently-skipped join. Whatever
defers `LiveRemove` past the end of the program does not defer the wait.

Two readings survive and neither is measured: `join` reaches its
`LiveRemove(Self)` with a `Self` the registry does not hold, or the rebound
loop variable routes the call somewhere that returns before that line. The
discriminator is a probe INSIDE `Thread.join` on the branch it takes, which is
five minutes and has not been spent.

## SEVERITY: A FALSE DIAGNOSTIC, AND IT REACHES NO DEMO

- The registry keeps corpses and reports an overflow that is not real — a
  diagnostic that exists to flag a genuine leak becomes noise that would hide
  one, which is the exact failure `LiveRemove` was written to fix.
- The exit-time join list is wrong for a program past 64 non-daemon threads.
- **No lost join and no lost thread**, per the measurement above.

Prio 65 -> 40 on lekkerzeilen-c8's three independent negatives: 0 of 104 demo
logs carry the warning; all four demo threads pass `daemon=True`, and
`Thread.start` only calls `LiveAdd` `if not daemon`, so the registry is never
written; and an AST census for this exact shape returns zero across the
package. (Their first census said 28 hits, then 3, both artefacts of a scope
walker that let module scope re-visit nested function bodies — recorded here
because the wrong number came with file:line citations that read as evidence.)

## WHY IT WAS NOT FOUND BY THE CONTROL THAT SHIPPED WITH LiveRemove

`mimic_threading.pas` records the control as *"100 threads started and joined
in a loop"* — `t.start(); t.join()` with no list. Measured here: that exact
shape prints **0** warnings on the broken build. It joins the element that was
added LAST every time, and it never rebinds anything.

This is `normalise-dont-special-case.md`'s ordered-list rule in another
subsystem — *the passing arrangements are not a sample, they are the population
everyone writes* — and `for t in ts:` after `ts.append(t)` is an extremely
ordinary thing to write.

Found while building the fixture for the pythreadlive liveness fix; the two are
unrelated defects that met in one file.
