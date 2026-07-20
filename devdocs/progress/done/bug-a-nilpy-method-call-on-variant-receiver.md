---
track: A
prio: 70
type: bug
---

# NilPy: calling a method on a VARIANT receiver is a parse error

Found 2026-07-20 alongside [[bug-nilpy-method-returning-str-garbage]].

## Repro

```python
class W:
    def __init__(self, n: str) -> None:
        self.n = n
    def name(self) -> str:
        return self.n

ws = [W("alpha")]
for w in ws:
    print(w.name())     # error: unexpected token (
```

Assigning the element to a typed local first is the workaround.

## Cause

A for-in loop variable is a VARIANT (every container slot is a 16-byte variant
slot), and the dotted-call path resolves a method by the receiver's static
class. A variant receiver has none, so `w.name()` does not parse as a call.

This is the same family as
[[bug-a-len-of-variant-picks-wrong-overload]]: an operation that Python
dispatches on the RUNTIME type, which pxx wants to resolve statically. Here
the object tag (VT_OBJECT, 7) does carry the instance pointer, so a runtime
dispatch is possible — but it needs the class identity, which the slot does
not currently record.

Note this makes "iterate a list of objects and call a method" — one of the
most ordinary Python shapes there is — unavailable, so it matters more than
the parse-error symptom suggests. `feature-nilpy-corpus-uforth` will hit it
immediately.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, the repro matching
CPython, plus the dict variant (`for k in d: d[k].method()`).

## Log
- 2026-07-20 — resolved, commit 31eff39b.
