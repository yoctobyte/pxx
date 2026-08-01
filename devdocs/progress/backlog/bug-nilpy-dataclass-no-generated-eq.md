---
track: N
prio: 30
type: bug
---

# `@dataclass` gets no generated `__eq__` — compares by identity instead of fields

Split out of
[[bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic]] (now
resolved for its four dispatch clusters), whose "Also measured" section
found this:

```python
from dataclasses import dataclass
@dataclass
class P:
    x: int
print(P(1) == P(1))     # CPython: True     pxx: False
```

CPython's `@dataclass` decorator generates `__eq__` comparing the declared
fields (and `__init__`/`__repr__`, but those already work per the sweep). pxx
compiles the decorator (init/field defaults land, per
`feature-nilpy-staticmethod-and-classmethod` and the songformatter ticket)
but does not synthesize `__eq__`, so `P(1) == P(1))` falls back to identity
comparison and is `False` where CPython says `True`.

Note this is a different root cause from the dispatch bug in the parent
ticket: a HAND-WRITTEN `__eq__` on an ordinary class IS honoured (see that
ticket's measured table — `__eq__`: yes/correct). Only the dataclass-generated
one is missing, i.e. the decorator's codegen needs to synthesize the method,
not that `__eq__` dispatch itself is broken.

## Suggested approach

Find wherever `@dataclass` field registration happens (`PyRegisterClassMembers`
per `feature-n-nilpy-ast-typing-module-scope`'s notes on the "dual
dataclass-table" path) and, when the class has no hand-written `__eq__`,
synthesize one that compares all declared fields — same shape as a
hand-written `def __eq__(self, other): return (self.f1, self.f2, ...) ==
(other.f1, other.f2, ...)` would produce, so it rides the already-working
`__eq__` dispatch path rather than needing a new one.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` regression
comparing a `@dataclass` equality result against CPython's actual output.
