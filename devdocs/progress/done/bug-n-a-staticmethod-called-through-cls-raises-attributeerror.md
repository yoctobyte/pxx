---
slug: bug-n-a-staticmethod-called-through-cls-raises-attributeerror
title: a staticmethod called through cls raises AttributeError
summary: >
  `cls.species(it)` inside a @classmethod answers
  `AttributeError: 'type' object has no attribute 'species'` for a
  @staticmethod the same class plainly declares. CPython returns the method.
  Class ATTRIBUTES through `cls` resolve correctly (`cls.SPAN` works), so the
  classref receiver reaches the attribute path and not the method path.
track: N
type: bug
prio: 70
owner: unassigned
status: done
---

## Repro

```python
class Chart:
    @staticmethod
    def species(it):
        return "chart"


class Plot:
    @classmethod
    def bucket(cls, items):
        out = ""
        for it in items:
            out = out + cls.species(it) + " "
        return out

    @staticmethod
    def species(it):
        return "tree" + str(it)


print(Plot.bucket([1, 2]))
```

CPython: `tree1 tree2 `. pxx at b46c98d433f1:
`Unhandled exception: AttributeError: 'type' object has no attribute 'species'`,
rc=217. Single file, no imports.

## What is and is not broken

| through `cls` | CPython | pxx |
| --- | --- | --- |
| `cls.SPAN` (class attribute, one declaring class) | ok | ok |
| `cls.SPAN` (two unrelated classes declare it) | ok | ok |
| `cls()` then an instance method on the result | ok | ok |
| `cls.species(...)` where `species` is a @staticmethod | ok | **AttributeError** |

So the receiver is boxed and routed (PyBoxClassRef -> the variant attribute
chain) and the ATTRIBUTE arms answer; it is the callable arm that finds
nothing. `pyclsattr_bind` is in the emitted code for the working rows.

## Where to look

The variant METHOD-call scan in `pyparser.inc` (`PyParseVariantMethod` and the
candidate arms below it) against a receiver whose tag is VT_CLASSREF rather
than VT_OBJECT. A staticmethod has no `self`, so the arity and the receiver
slot do not line up with the instance-method shape the arms are built around;
the likely answer is a classref arm that reflects the name over the class blob
the way `PyClassRefNew` already reflects `create`.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` carrying the four
rows above with expectations from CPython -- the three correct rows matter as
much as the wrong one, because they localise this to the callable arm.

## Log
- 2026-09-14 -- found while reducing lekkerzeilen's `App._bucket` crash, which
  is a @classmethod that calls a @staticmethod through `cls`. That crash turned
  out to be a different bug (the RTTI walk, now fixed in
  `done/bug-n-a-class-reference-receiver-walks-rtti-off-a-non-instance`); this
  one fell out of the reduction and is real on its own.

## Fixed 2026-11-10

PyClassLevelCarrier gives up when two classes declare the name as a static
(Chart.species and Plot.species). It is right to: through an arbitrary class
VALUE, only an identity test on the blob could choose. But inside a
@classmethod whose class nothing derives from, `cls` can only BE that class.
PyParseVariantMethod now checks this before the receiver is hoisted. When the
receiver is the classmethod's own `cls` and the class is no one's base, it
uses the class's own static/class method as the single carrier, through the
existing class-value arm.

Still open, and not this ticket: `cls.kind()` where a SUBCLASS overrides the
static `kind` (polymorphic `cls`) still raises. That needs the run-time
identity test described in PyClassLevelCarrier's header.
Test: test/test_nilpy_a_staticmethod_called_through_cls.py, with expected
output = python3.
