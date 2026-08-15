---
track: N
prio: 35
type: bug
blocked-by: []
summary: "Assigning a nested def's value to an OUTER name of the same spelling — `g = make(); def g(...)` inside make — binds None: the call raises \"object is not callable — the name is None\". Renaming either one fixes it."
---

# A nested def shadowed by an outer name binds to None

```python
def make3(base):
    def g(x, off=base):
        return x + off
    return g

g = make3(10)          # the OUTER name is also `g`
print(g(1))            # CPython 11
                       # pxx: TypeError: object is not callable — the name is None
```

Rename either the outer variable or the inner def and it works. Reproduces on
`pinned` (v327); found 2026-08-15 while testing
[[bug-nilpy-a-nested-defs-default-parameter-ignores-the-callers-value]], where
the first draft of the test hit it by accident.

Loud, but the message blames the wrong thing: it says the name is None "(an
import that did not resolve, or a value never assigned)" when the value WAS
assigned — from a call whose return value went missing.

## Where to look

The nested def is registered under a qualified name (`make3.g` — see
`PyQualifyNested`, which exists because an unqualified `FindProc` lands on the
bodyless pre-pass shell). The outer `g` is a module binding of the same
spelling. One of the two lookups is picking the other's row: either the assign
resolves `make3(10)`'s result against the nested proc's name, or the later
`g(1)` resolves the MODULE name to the nested shell. `PXXDBG=n.shadow` exists
for exactly this question and is the first thing to run.

Worth checking the same shape for a class (`C = make_class()` returning a nested
class) and for a def whose name matches an enclosing PARAMETER.

## Gate

`.npy` diffed against CPython: the shape above; the same with the inner def
capturing nothing; a second call through the outer name; the name reused for a
DIFFERENT nested def from a second factory; and controls with distinct names.
