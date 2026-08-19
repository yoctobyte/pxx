---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`X.attr` where X came from an import that did not resolve is compiled as the BARE NAME `attr`, so `ModuleType.__name__` fails with `undefined variable (__name__)` — a message naming the attribute and never the unresolved import that caused it. Now the first wall on 4 html5lib files."
status: working
owner: frankonpiler-an
---

# An attribute on an unresolved import degrades to a bare name

```python
from types import ModuleType
print(ModuleType.__name__)     # error: undefined variable (__name__)
```

`types` does not resolve, so `ModuleType` binds to nothing — and instead of
saying so, the qualified `ModuleType.__name__` is compiled as if `__name__`
were a bare name in scope. The diagnostic then names the ATTRIBUTE and never
mentions the import that actually failed, which is the whole cost: the message
points at the wrong line.

Contrast, same build, which is what shows it is the unresolved-base path and
not `__name__` itself:

| shape | result |
| --- | --- |
| `class K: pass` then `K.__name__` | `K` — correct |
| module-level `__name__` | `__main__` — works |
| `import sys` then `sys.__name__` | a clean runtime error that NAMES the unresolved import |
| **`from types import ModuleType` then `ModuleType.__name__`** | **`undefined variable (__name__)`** |

The `sys` arm is the model to follow: it fails, but it says *"this build has no
`sys.__name__`: the import it came from could not be resolved"*. That is the
message the `types` arm should give too. Same concept, two paths, and the
second one is the broken one —
`devdocs/dev/normalise-dont-special-case.md`.

## Why it matters now

It is the first wall on **4 html5lib files** (`_utils.py`, `serializer.py`,
`treebuilders/__init__.py`, `treewalkers/__init__.py`), all reaching it through
the single site `_utils.py:126`:

```python
name = "_%s_factory" % baseModule.__name__
```

They arrived here by moving PAST `unknown base class Mapping` when
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]
was fixed — so this is the next rung, not a regression.

## Note on scope

Two fixes are available and they are not alternatives. **The diagnostic** should
name the unresolved import (cheap, and it is what makes the next such wall
self-explaining). **The behaviour** — whether `types.ModuleType` should resolve
at all — is a separate question about how much of `types` NilPy models. Do the
diagnostic first; it is what turns every future instance of this shape from a
misleading message into a correct one.

## Provenance

Found 2026-08-19 by frankonpiler-an while measuring the corpus effect of the
`collections.abc` import fix. Reproduces on `PXX_STABLE` as well once the
`Mapping` wall is out of the way.


---

## 2026-08-19 — INVESTIGATED. My own root cause above is WRONG. The import RESOLVES.

I filed this ticket and its diagnosis is wrong. `types` is **not** an unresolved
import: **`lib/rtl/types.pas` exists** — a *Pascal* RTL unit that happens to
share its name with a Python stdlib module. `from types import ModuleType`
resolves to that unit, which of course exports no `ModuleType`, and the failure
surfaces one token to the right.

Measured, not reasoned. `PXXDBG=a.qual` traces the qualifier path, and the
`undefined variable` sites were temporarily tagged with their line numbers to
find which one fires (`compiler/parser.inc:5250`, the class/static-member arm).
The tags have been removed; the `a.qual` probe was already in the tree.

### The real finding is a HAZARD CLASS, not one bad message

Eight `lib/rtl/*.pas` units share a name with a Python stdlib module:

```
classes  io  json  math  random  re  strings  types
```

Most are deliberate — `lib/rtl/re.pas` says in its own header *"Python's `re`
module for the Nil-Python frontend"*, and `math` and `json` work correctly. The
hazard is the ones that are **Pascal** units wearing a Python module's name:

| import | result |
| --- | --- |
| `from math import pi` | correct (3.1416) |
| `from json import dumps` | correct |
| `from types import ModuleType` | `undefined variable (__name__)` — names the attribute, not the import |
| `from strings import Foo` | `undefined variable (Foo)` — at least names the right thing |
| **`from classes import Foo`** | **`error: no overload of Delete matches these arguments`** |

That last row is the worst of them: importing it drags Pascal's `classes` unit
into a NilPy compile and fails somewhere inside that unit, with a message about
`Delete` that names nothing the program wrote. A reader has no path from the
diagnostic back to the import.

### So there are two separable pieces of work here, and neither is what the title says

1. **The collision itself.** A NilPy `import X` should not silently bind to a
   Pascal RTL unit named `X` that is not a NilPy module or a `mimic_` shim.
   Whether the right answer is a refusal naming the collision, a namespace
   split, or a `mimic_types`, is a design call — **Track U**, not a guess.
2. **The diagnostic**, which is what this ticket originally asked for and is
   worth doing either way: when a member lookup through a qualifier fails, name
   the receiver as well as the member.

### Also corrected: `re.MULTILINE` is NOT a collision

The next wall on the tinycss2 files is `undefined variable (MULTILINE)`, and I
had it queued as possibly this same bug. It is not: `lib/rtl/re.pas` **is**
NilPy's `re`, deliberately, and it simply does not define `MULTILINE` yet. That
is an ordinary **Track B library-surface gap**, which matches the coordinator's
read that the remaining corpus distance is turning into missing surface rather
than mechanism bugs.

### Status

Investigation only — **no code changed**. A guard I tried (refusing to register
a unit alias for a module that did not resolve) turned out to fix nothing here
and was reverted rather than landed unverified.

Second ticket today whose diagnosis I wrote and had to retract; both times the
mistake was inferring a cause from one observation (`pyvartag = 12` → "the
boundfn carrier"; "no such Python module" → "unresolved import") instead of
printing which path actually ran. The correction is recorded here rather than
edited away.
