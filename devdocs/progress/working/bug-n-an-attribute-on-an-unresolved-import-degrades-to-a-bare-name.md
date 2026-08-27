---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`X.attr` where X came from an import that did not resolve is compiled as the BARE NAME `attr`, so `ModuleType.__name__` fails with `undefined variable (__name__)` — a message naming the attribute and never the unresolved import that caused it. Now the first wall on 4 html5lib files."
status: working
owner: frank1-AN
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

---

## 2026-08-27 — RESOLVED. Piece 1 was already fixed; piece 2 is what landed.

The 2026-08-19 investigation split this into two pieces and said neither was
what the title said. Re-measured today on HEAD, both halves have moved:

### Piece 1 (the collision) is already fixed — by someone else, since

The two worst rows in the investigation's table now name the collision exactly:

```
from types import ModuleType
  -> import: types is the Pascal unit .../lib/rtl/types.pas, not a Python
     module — a bare NilPy import resolves to Python (.py/.npy) only. To reach
     the Pascal unit, name it with its extension: import 'types.pas' as types

from classes import Foo
  -> the same message, naming lib/rtl/classes.pas
```

That is `pasparser_proc.inc`'s "THE COLLISION, NAMED" guard. So the design call
this ticket wanted to send to Track U has been made and implemented, and
`classes` — the row the investigation called the worst of them, failing inside
Pascal's unit with a message about `Delete` — is gone.

All eight colliding names, measured today with `import X` + `X.NoSuchThing`:

| name | verdict |
| --- | --- |
| `classes`, `types` | refused, collision NAMED — correct |
| `io`, `json`, `math`, `re` | resolve as NilPy modules — correct, and the member error now names the qualifier |
| `strings` | resolves to something; members do not answer |
| `random` | the qualifier itself is undefined (`random.f` flat-resolves, `random.NoSuchThing` does not) |

### Piece 2 (the diagnostic) is what this commit does

*"When a member lookup through a qualifier fails, name the receiver as well as
the member"* — the half the investigation said was worth doing either way.

```
import strings
print(strings.Foo)

  was:  error: undefined variable (Foo)
  now:  error: no member Foo came of the qualifier strings — check what
        strings resolves to; an import that bound nothing gives exactly
        this (strings.Foo)
```

`PyQualifierBefore(identTok)` reads the dotted receiver back off the TOKEN
STREAM. `ParseLValueAST` hands its NilPy half only `(idx, identTokIdx)`, and by
the time a member lookup has failed every arm that could have resolved the
receiver has consumed it — threading it down would mean passing it from a dozen
sites, each a chance to pass the wrong one. What the user *wrote* is one place
and cannot drift from itself.

Only a plain dotted chain is named: `a[i].Foo` and `f(x).Foo` answer `''` and
keep the short message, because there is no short phrase for those receivers
and a half-right one in a diagnostic is worse than none.

**The cause is deliberately not claimed.** This site cannot tell a receiver that
resolved to nothing from one that resolved and has no such member. Guessing
between them is precisely how this ticket's own original root cause came out
wrong — twice, as the 2026-08-19 note records. The message states only what is
known: the qualified name the user wrote, and that no member came of it.

The Pascal half (`pasparser_lval.inc:85/89`) is deliberately left alone. The two
parsers are duplicated across languages on purpose
(`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`), and Pascal has no
unresolved-import path that reaches this arm the same way.

### Tests

- `test_nilpy_qualified_name_error_names_the_receiver` — the qualifier is named,
  exit 1, no binary emitted.
- `test_nilpy_bare_name_error_stays_short` — the **control**: a genuinely bare
  undefined name keeps `undefined variable (Foo)`. Inventing a receiver where
  the user wrote none would be the same defect pointing the other way. Two files
  rather than two lines because this site calls `Error`, not `ErrorRecover`, so
  one compile reports one error.

Both registered in the Makefile beside the other NilPy diagnostics.

### Left open, filed separately

- **`random` is never seeded and its first draw is the low bound** — found while
  sweeping the eight colliding names. `random.randint(1,100)` gives the same
  sequence every run and always opens with `1`. Filed as
  [[bug-b-nilpy-random-is-never-seeded-and-its-first-draw-is-the-low-bound]]
  (Track B, p60).
- **`strings`** resolves to something whose members do not answer, unlike
  `types`/`classes` which are refused outright. Not chased: the new diagnostic
  now makes it self-explaining at the point of use, which is what this ticket
  was for.

### Gate

`make compiler/pascal26` — self-host fixedpoint `100300ef2b3a`, converged in 1
round. Both new tests pass, verified by running the Makefile's own assertions.
