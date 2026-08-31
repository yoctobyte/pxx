---
slug: bug-n-property-works-as-a-decorator-but-is-not-a-builtin-name
track: N
prio: 30
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
summary: "@property compiles and works, but `property` as a plain builtin NAME does not exist: `v = property(getter)` and `v = property(getter, setter)` both give `undefined variable (property)`. Real CPython code uses the callable form for read/write properties, because @property.setter needs the decorator pair and the two-arg call is the older, shorter spelling. Blocks html5lib's treebuilders/base.py:321 and therefore the whole dom treebuilder."
---

# `@property` works; `property(...)` as a name does not exist

- **Track N** (Nil-Python frontend). Found by frankB on 2026-08-30 while working
  [[feature-b-a-real-minidom-is-an-implementation-not-a-shim]], which cannot
  reach its own stated gate until this is fixed — see "Why this matters" below.
- **Filed under N, not B**, per the rule that a frontend gap an app forces is
  filed in the owning lane rather than worked around in the library.

## Measured, against pin v393 (`1d69760deabe2865`) — and re-confirmed on v394 (`e2ea9034a65ea8b6`)

| form | result |
| --- | --- |
| `@property` decorator on a method | **COMPILES**, prints the right value |
| `v = property(_g)` — one-arg callable | **FAILS**: `error: undefined variable (property)` |
| `v = property(_g, _s)` — getter + setter | **FAILS**: `error: undefined variable (property)` |

The pin moved to v394 mid-investigation, so the table was re-run against it
rather than left citing ground that had shifted: identical results, and
`html5lib/treebuilders/base.py:321` still gives `undefined variable (property)`
on v394. Both pins say the same thing.

So the decorator *syntax* is handled, but the builtin `property` is not bound as
a name that an expression can reference. The diagnostic is accurate and points
at the right token; it is the capability that is missing, not the error.

Repro, self-contained:

```python
class C:
    def _g(self):
        return self._x
    def _s(self, n):
        self._x = n
    v = property(_g, _s)      # undefined variable (property)

c = C()
c.v = 7
print(c.v)
```

## Why the callable form is not an exotic spelling

It is how real code writes a **read/write** property when the getter and setter
already exist as named methods — the decorator pair (`@property` +
`@v.setter`) requires writing them as a matched pair under one name, which is a
refactor rather than a translation. Every library that predates the decorator
pair, or that computes its properties, uses the call.

`html5lib/treebuilders/base.py:321`:

```python
insertFromTable = property(_getInsertFromTable, _setInsertFromTable)
```

`html5lib/treebuilders/dom.py:121` uses the one-arg form:

```python
nameTuple = property(getNameTuple)
```

## Why this matters beyond one file — the wall order it sits in

The dom treebuilder's blockers, measured in the order the compiler hits them:

| # | wall | lane | state |
| --- | --- | --- | --- |
| 1 | `import weakref` | B | **cleared** 2026-08-30 (`lib/rtl/mimic_weakref.py`) |
| 2 | **`property(...)` as a name** | **N** | **this ticket** |
| 3 | `from xml.dom import minidom` binding nothing | B | [[feature-b-a-real-minidom-is-an-implementation-not-a-shim]] |

Wall 2 sits **between** two Track B walls, which is the point of filing it: the
minidom ticket's stated payoff is *"unblocks exactly one corpus file"*, and no
amount of Track B DOM work reaches that payoff while this stands. A DOM built
today is gated by its own CPython differential, not by the corpus file, and that
should be said plainly rather than discovered at the end.

## Scope note for whoever takes it

Only the *name* is missing — the descriptor machinery evidently works, since the
decorator form produces a real property with correct get behaviour. So this may
be binding an existing builtin rather than implementing one. Confirm that before
sizing it: if `@property` is handled by desugaring in the parser rather than by a
real `property` object, the two forms may not share an implementation at all,
and the callable form is the larger job. Do not assume from the decorator's
success that the object exists.

Setter behaviour is untested here because the callable form never compiles —
whoever fixes it should assert `c.v = 7; c.v == 7` by value, not just that the
form compiles.
