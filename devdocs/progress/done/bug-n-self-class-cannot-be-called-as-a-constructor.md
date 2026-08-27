---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`self.__class__(args)` does not compile — `error: A has no method __class__` — while `self.__class__.__name__` reads fine and `type(a).__name__` works. Calling the class object is the standard Python idiom for 'construct another one of my own type', and it is what CPython's own xml.sax AttributesImpl.copy() does; lib/rtl/mimic_xml_sax_xmlreader.py names its class explicitly instead, registered in track-b-workarounds.md."
status: done
owner: frank1-AN
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

## Resolution — 2026-08-27

Fixedpoint `85391dfb6ddf`, `tools/gate.sh quick` GREEN.
Test: `test/test_nilpy_self_class_constructs.npy` + `.expected`, 9 rows, all
matching CPython, registered in the Makefile.

**No new representation was needed** — that is the whole shape of the fix. The
refusal this ticket reports was written when it was TRUE ("this frontend has no
class-object value") and stopped being true when
[[feature-nilpy-class-as-a-value]] landed VT_CLASSREF. So a bare `x.__class__`
now lowers to exactly the classref variant a class held in a variable already
is, and construction rides `pyvar_callvN -> PyClassRefNew`, which already
reflects `create` by name over the RTTI. No second construction path.
`cls = self.__class__`, `print(self.__class__)`, `self.__class__ is B` and
`isinstance(x, self.__class__)` all came along for free, because none of them
was ever about `__class__`.

**The RUNTIME class, deliberately.** In a base method `self.__class__` must
answer the SUBCLASS — that is the entire reason the idiom exists. A static
`ci` would have been easy and would have silently constructed the base for every
descendant: a wrong VALUE, which is strictly worse than the compile error it
replaced. So the blob comes from `__pxxRttiOf(x)` (`[[x+0] - 8]`), the same
pointer `x.ClassType` is. Every `B` row in the test is there to hold that down.

**Four routes, because that is how many there are.** `PyIsBareClassRefAhead` +
`PyMakeClassRefOf` (pyparser.inc) are tested right after the existing
`__class__.__name__` chain check at all three of its sites — pasparser_lval.inc
and two in pyparser.inc — which keeps the `__name__` chain on its own direct
lowering instead of boxing a classref only to read a name back off it. The
fourth route is a receiver whose tag is only known at RUN time (an unannotated
parameter, a for-loop element, a dict value); that one is answered in
`pydynattr_get_v`, and the same arm went into `pydynattr_get` so the two getters
agree — the pairing that file's own comments keep calling out.

**One sibling fixed on the way:** `isinstance(x, a.__class__)` was
`unexpected token`. isinstance already routes a non-identifier second argument
to the runtime `pyisinstance_v`, and already routed a module-qualified
`mod.Class` there — but an identifier CARRYING A SELECTOR missed the arm by one
token and fell into the name arms, none of which consume a `.`. The condition
now also admits `ident .`.

**Two pre-existing limitations found by the sibling sweep, both measured
identical on pinned v384, both filed rather than folded in:**

- [[bug-n-an-attribute-off-a-call-returning-a-class-value-does-not-parse]] —
  `P(7).mk().a` is a parse error when `mk` returns a classref construction AND
  the class has a subclass. Needs both; neither alone does it. Repro written
  with `cls = P` so it needs no `__class__` at all, because it is not this
  ticket's doing — `self.__class__(...)` only makes it easy to reach.
- [[bug-n-a-keyword-argument-through-a-class-value-is-refused-at-runtime]] —
  `self.__class__(x, b=99)` raises a TypeError whose message says a class value
  "carries no parameter names". `defs.inc` says it does, and names
  `PyClassRefNew` as the reflected caller that reads them, so the message is
  out of date and that is the lead.

**Track B workaround marked REVERTABLE** in `devdocs/dev/track-b-workarounds.md`
— `lib/rtl/mimic_xml_sax_xmlreader.py`'s `AttributesImpl.copy` /
`AttributesNSImpl.copy` name their class explicitly. Not reverted here: that is
Track B's file and its lifecycle, and it wants the next pin under it first.

## Log
- 2026-08-27 — resolved, commit f34b1851b.
