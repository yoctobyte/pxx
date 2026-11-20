---
slug: bug-n-a-dataclass-that-inherits-a-dataclass-segfaults-on-construction
track: N
prio: 65
type: bug
status: done
owner: rd
created: 2026-11-20
found-by: rd
tags: [nilpy, dataclass, inheritance, crash]
blocked-by: []
summary: "@dataclass Kid(Base), both with fields: Kid(1, 2.5) compiled and segfaulted (CPython prints 1 2.5). The generated ctor took Kid's own fields only."
---

# A dataclass that inherits a dataclass segfaults on construction

```python
@dataclass
class Base:
    a: int

@dataclass
class Kid(Base):
    b: float

k = Kid(1, 2.5)
print(k.a, k.b)       # CPython: 1 2.5   pxx: Segmentation fault (rc 139)
```

Found while fixing
bug-n-a-dataclass-field-coerces-what-its-generated-ctor-is-given-into-the-annotation.

## Cause

pxx keeps each class's own fields in its own window (UClsFBase/UClsFCount).
The generated `create` ctor, the call site's argument fill (positional,
keyword and trailing defaults), `__eq__`, `__repr__` and the order dunders
all read that window. So Kid's ctor took only `b`, and two arguments ran
off a one-parameter procedure. CPython's generated `__init__` takes the
fields of every dataclass base first, then its own.

## Fix (pyparser.inc)

- A FLAT field index: PyDcFlatChain (ci plus its dataclass ancestors, root
  first; a plain base's attributes are not fields, as in CPython),
  PyDcFlatCount, PyDcFlatField (flat number to owning class and index),
  PyDcFlatIndexOf (name to flat number) and PyDcFlatUFld.
- The ctor's registration and body, the call site's keyword lookup, hole
  fill and trailing fill, and the Eq, Repr and Order bodies use it.
- PyDcDefaultNode takes a flat number and remaps it to the owning class's
  own PyDc* rows, so an inherited default works.
- The header sweep sets PyDcClassIsDc before registering a class, so a
  subclass registered there sees its bases as dataclasses.
- Generated `__eq__`, `__repr__` and the order dunders are skipped only when
  the class's OWN body defines one (PyDcOwnsMeth), not when an inherited one
  exists. That is CPython's rule, and without it Kid printed as `Base(a=..)`.

## Measured

test/test_nilpy_dataclass_inherits_a_dataclass.npy is a test-nilpy row,
diffed against CPython. It covers positional arguments, inherited and own
defaults, a keyword past a defaulted base field, repr, eq over all fields,
order=True on a subclass, a plain (non-dataclass) base, and a hand-written
`__repr__` in the subclass. All of it is identical to CPython.
