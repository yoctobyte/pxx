---
track: N
prio: 50
type: bug
---

# A call whose managed-string result is DISCARDED leaks it

```python
def flabel(v: int) -> str:
    return str(v)

while i < n:
    flabel(7)          # result dropped
    i = i + 1
```

RSS slope, 20k vs 320k iterations: **952 KB -> 10296 KB**. Binding the same
result to a name is flat (`s = flabel(7)`), and so is consuming it
(`len(flabel(7))`). Only the DROPPED result leaks — the callee hands back a
handle at +1 and nothing ever releases it, because there is no store to carry
the ownership.

Affects plain defs and methods alike, so it is not the method-vs-def divergence
[[bug-nilpy-method-returning-a-fresh-string-leaks]] fixed (that one was a double
RETAIN at the store; this one is a missing RELEASE where there is no store).
Both were measured in the same session; this one was left because it is a
different mechanism in a different place.

~32 bytes an iteration, silent. The shape is ordinary: a method called for its
side effect that happens to return a string (`buf.append_line(...)` returning
the new text, a logger returning what it logged).

## Where to look

The statement-expression path: when an expression statement's value is a managed
type and is not stored anywhere, it needs a release after evaluation — the same
scope-exit treatment a hidden temp gets. `IRIVal[node] := 1` marks a call
emitted for effect (see IRAppendCall's callers); that marker is the natural
place to decide the result needs dropping.

Check the same shape for a discarded OBJECT result and a discarded variant while
there — an object result carries the callee's return-retain
([[bug-nilpy-returning-a-construction-leaks-one-ref]]), so it should leak
identically.

## Gate

`make test-nilpy` + self-host byte-identical, plus RSS-slope pairs for a
discarded string result from a def, from a method, and a discarded object
result — all flat.
