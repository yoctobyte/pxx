---
slug: bug-n-a-dataclass-that-inherits-a-dataclass-segfaults-on-construction
track: N
prio: 65
type: bug
status: backlog
owner: ""
created: 2026-11-20
found-by: rd
tags: [nilpy, dataclass, inheritance, crash]
blocked-by: []
summary: "@dataclass Kid(Base), both with fields: Kid(1, 2.5) compiles and the program segfaults (CPython prints 1 2.5). The same on 8d3a09db2f, before the dataclass ctor-join change."
---

# A dataclass that inherits a dataclass segfaults on construction

```python
from dataclasses import dataclass

@dataclass
class Base:
    a: int

@dataclass
class Kid(Base):
    b: float

k = Kid(1, 2.5)
print(k.a, k.b)       # CPython: 1 2.5   pxx: Segmentation fault (rc 139)
```

Measured 2026-11-20 on 8d3a09db2f and on the tree with
bug-n-a-dataclass-field-coerces-what-its-generated-ctor-is-given-into-the-annotation,
with the same result both times. The compile succeeds with no diagnostic.

CPython's generated `__init__` for Kid takes `(a, b)`: the base's fields
first, then its own. The likely place is the generated constructor's
argument and field mapping (the PyDc* tables, which are filled per class),
not this ticket's join. Found while writing that ticket's test, which
leaves the inherited case out and points here.
