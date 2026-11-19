---
slug: bug-n-a-dataclass-field-coerces-what-its-generated-ctor-is-given-into-the-annotation
track: N
prio: 65
type: bug
status: done
owner: rd
created: 2026-11-19
found-by: rd
tags: [nilpy, dataclass, annotation, wrong-value]
blocked-by: []
summary: "@dataclass `x: float` given a str stores its pointer bits as a double (prints 2.457953e-317, CPython prints hi); given an int it prints 3.0 (CPython: 3). A WRONG VALUE with no diagnostic. The plain-class twin is right, because its stores are joined; the generated ctor's are not."
---

# A dataclass field coerces what its generated ctor is given into the annotation

Measured 2026-11-19 at 09ae12f48c (the same on 2755a79344):

```python
from dataclasses import dataclass

@dataclass
class V:
    x: float

def mk(a):
    return a

print(V(mk("hi")).x)   # pxx: 2.457953e-317   CPython: hi
print(V(mk(3)).x)      # pxx: 3.0             CPython: 3
```

Python does not enforce annotations, so `x` holds whatever was passed. pxx
types the field from the annotation (double) and the generated constructor
stores its variant argument into that double slot. A str arrives as its
pointer bits, and an int as a float. Nothing is reported.

## Why the plain class is right and this is not

A plain class's field type comes from the join over every store
(`PyCollectClassFieldJoins` / `PyFJ*`): `self.x = x` with an argument of
unknown type joins to a variant, and the str survives. The dataclass arm
widens its annotation by that join too, but the GENERATED ctor's stores are
not `self.NAME = ...` statements, so the join never sees them. The arm
trusts the annotation alone.
(Noticed while working
bug-n-a-class-level-field-annotation-is-discarded-unless-the-class-is-a-dataclass,
whose prescribed fix, giving plain classes this same annotation trust, was
measured as wrong for exactly this reason and not landed.)

## The direction

Join the construction sites' argument types into the field, the way the
plain class's stores are joined: a call `V(a)` is a store of `a` into
`V.x`. A variant argument then makes the field a variant, and the common
case (`V(1.5)`) stays a double. Refusing would be wrong: CPython accepts it.

## Resolution (2026-11-20, rd)

As the direction above says: `PyFJJoinDataclassCtorCalls` (pyparser.inc,
run after PyFJJoinForeignStores in the detect phase) treats every call
`V(...)` to a dataclass as the stores its generated constructor performs.
Positional arguments go into the fields in declaration order (a dataclass
base's fields first, as CPython orders them; a redeclared base field keeps
its place), keywords go by name, and each argument is typed by
PyFJForeignRhsTk. An argument it cannot type, or any star argument, makes a
scalar or class field a variant. The dataclass arm already widened its
annotation by the join; now the join has something in it. The phase-0 sweep
records `PyDcIs` and the body span per class for this.

Measured, on test/test_nilpy_dataclass_field_holds_what_the_ctor_is_given.npy
(a test-nilpy row, diffed against CPython): `V(mk("hi")).x` gives hi and
`V(mk(3)).x` gives 3, a keyword `y=mk("kw")` and `V(*args)` are right, and
`Fast(1.5, 2.5)` keeps `r_fast`'s q a double (tk=19, pinned by the row).

Not covered: a construction the token scan cannot see as `V(...)` (through
an alias, `cls(...)` in a classmethod, `dataclasses.replace`) still has only
the annotation. Separately found and filed:
bug-n-a-dataclass-that-inherits-a-dataclass-segfaults-on-construction
(already on master before this change).
