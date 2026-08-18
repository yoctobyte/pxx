---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`self.__class__(args)` does not compile — `error: A has no method __class__` — while `self.__class__.__name__` reads fine and `type(a).__name__` works. Calling the class object is the standard Python idiom for 'construct another one of my own type', and it is what CPython's own xml.sax AttributesImpl.copy() does; lib/rtl/mimic_xml_sax_xmlreader.py names its class explicitly instead, registered in track-b-workarounds.md."
---

# `self.__class__(...)` cannot be called as a constructor

- **Type:** bug — **Track N** (Nil-Python frontend).
- **Found:** 2026-08-18 by frank3-fc, transcribing CPython's
  `xml.sax.xmlreader.AttributesImpl.copy` for
  [[feature-b-module-shims-for-the-html5lib-corpus]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).

## Repro

```python
class A:
    def __init__(self, v):
        self.v = v
    def clone(self):
        return self.__class__(self.v)   # error: A has no method __class__

print(A(7).clone().v)
```

CPython prints `7`.

## The boundary

| shape | result |
| --- | --- |
| `self.__class__.__name__` | OK — reads `A` |
| `type(a).__name__` | OK — reads `A` |
| `self.__class__(self.v)` | **error: A has no method __class__** |

So `__class__` resolves as something you can read an attribute off, but not as
a class object you can call. The diagnostic is also misleading: it reports a
missing *method* `__class__` on a class whose `__class__` attribute demonstrably
works one line earlier.

## Why it matters beyond the diagnostic

`self.__class__(...)` is the idiom for "make another one of me", and its point
is that a SUBCLASS gets an instance of itself. Naming the class explicitly —
the only workaround — silently changes that: `Base.copy()` called on a
`Derived` returns a `Base`. So this is not a spelling preference; the two forms
mean different things, and only the unsupported one is correct for a class
anyone might subclass.

## Track B site

`lib/rtl/mimic_xml_sax_xmlreader.py` (`AttributesImpl.copy`,
`AttributesNSImpl.copy`) names the class explicitly and says so at the site.
Registered in `devdocs/dev/track-b-workarounds.md`; revert to the `__class__`
form when this lands.
