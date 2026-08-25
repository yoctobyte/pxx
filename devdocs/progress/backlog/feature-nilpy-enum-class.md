---
track: N
prio: 62
type: feature
---

# `from enum import Enum` — enum classes are not supported

```python
from enum import Enum

class Color(Enum):
    RED = 1
    GREEN = 2

print(Color.RED, Color.RED.name, Color.RED.value)   # Color.RED RED 1
print(Color.RED == Color.GREEN)                      # False
for c in Color:                                      # iterates members
    print(c.name, c.value)
```

```
pascal26:1: error: import: no unit named enum and no shim mimic_enum
```

Walls visibly at the import, which is the right failure — nothing silent here.

**11 of the neuzelaar corpus's 168 files**, so it ranks behind `@dataclass` (60)
and f-strings (70) but ahead of most of the census
(`feature-nilpy-thirdparty-libraries-as-targets`).

## The shape of the work — NOT just a shim unit

The import error suggests a `mimic_enum` unit would do it. It would not: the
semantics are in the CLASS, not the module. What `Enum` actually means:

- class-level `NAME = value` assignments become **member instances**, not
  ordinary class attributes — `Color.RED` is a `Color`, not `1`
- each carries `.name` (the identifier as a string) and `.value`
- `str()` is `Color.RED`, not `1` — and `repr()` differs again
- the CLASS is iterable, in declaration order
- members compare by identity; two members with the same value are aliases
- `Color(1)` looks a member up BY VALUE, `Color["RED"]` by name

NilPy already registers class-level constants (`PyClsAttr*`) and now generates
dunders for `@dataclass` (`PyEmitDataclassRepr`/`Eq`), so the machinery to
synthesize per-class behaviour from a decorator-or-base marker exists. This is
the same shape of job one level up: recognise `class X(Enum)`, convert the
attribute table into members, synthesize `__str__`/`__repr__`/`__eq__` and make
the class iterable.

`IntEnum`/`StrEnum`/`auto()` are follow-ons, not part of this.

## Gate

`make test-nilpy` + self-host byte-identical. A test diffed against CPython
covering: member access, `.name`/`.value`, `str`/`repr`, `==` between members
and against a bare int, class iteration order, and lookup by value and by name.
