---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`class Filter(base.Filter)` is refused with \"class Filter cannot inherit from itself\" — a QUALIFIED base class is compared by its last component only, so a subclass that keeps its base's name is misread as its own descendant. CPython accepts and runs it. Now the wall on three html5lib files, and the most common non-import error left in that corpus."
status: done
owner: frank2
---

# A qualified base class named like its subclass is rejected as self-inheritance

- **Type:** bug (name resolution) — **Track N** (NilPy class declaration).
  Possibly shared: the qualifier is dropped somewhere between `ConsumeUnitQualifier`
  and the base-class identity check, and that check may live in `parser.inc`.
- **Found:** 2026-08-17 by frank2, measuring what was behind the wall cleared by
  [[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]].
- **Measured at:** HEAD `65d26b24c` — a native self-hosted build, not `pinned`.

## Repro — eight lines, no packages, no shims

`base.py`:

```python
class Filter(object):
    def name(self):
        return "base"
```

`prog.npy`:

```python
import base

class Filter(base.Filter):
    def name(self):
        return "derived"

print(Filter().name())
```

```
CPython: derived
pxx:     pascal26:3: error: Nil Python: class Filter cannot inherit from itself
                    — a base class must not be the class being declared, nor one
                    of its descendants
```

Rename **only the subclass** and it compiles and prints `derived`:

```python
class Other(base.Filter):   # ok
```

So the base class is fine, the module is fine, the inheritance is fine. The only
thing that fails is the two names being spelled the same — which means the check
is comparing `Filter` against `Filter` after having thrown the `base.` away.

## Why it matters

Re-exporting a base under its own name is ordinary Python, and html5lib does it
throughout: `html5lib/filters/whitespace.py` is exactly `class Filter(base.Filter)`,
and so are `filters/alphabeticalattributes.py`, `filters/inject_meta_charset.py`,
`filters/lint.py`, `filters/optionaltags.py`, `filters/sanitizer.py`. In the
58-file scan of `html5lib`/`tinycss2`/`webencodings` this is the **most common
error left that is not a missing import** (3 files at the point of measurement,
and it becomes more once the module-locals cap in
[[bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow]] stops
short-circuiting them earlier).

## Note on family

This is the same shape as the bug it was found behind: a name reached through an
explicit qualifier having the qualifier ignored by a downstream check that was
written for the bare case. Worth grepping the base-class path for any other
comparison against a class name that takes the identifier without asking whether
it was qualified — `devdocs/dev/normalise-dont-special-case.md`, and the fifth
instance recorded on [[meta-a-second-paths-reimplement-the-first-paths-decisions]].

## Root cause — and the ticket UNDERSTATED it

*(frank2, 2026-08-18, measured at `dcef86b59`. The loud half is what got filed;
the silent half is the one that mattered.)*

`PyRegisterClassShells` (`pyparser.inc`) pre-registers a shell row for every
`class NAME` token it scans, guarded by **`FindUClass(name) < 0` — a flat,
unit-blind test**. So once the main program has shelled `Filter`, an imported
`.py` module declaring its own `Filter` registers **no shell of its own**, and
`PyParseClass`'s equally flat `ci := FindUClass(CurTok.SVal)` then hands that
module's declaration the PROGRAM's row. One row, two different classes.

Measured directly: at the failing site there was exactly **one** `Filter` row,
`unitIdx = -1` (the program). In the working control there were two, `unitIdx`
612 and 614. The rows for the modules' classes were not wrong — they did not
exist.

### The half the ticket missed

The self-inheritance error is only the loud face. The same merge produces a
**silent wrong answer** whenever the subclass is named differently:

```python
import other                       # other.py: class Filter -> "other"

class Filter(object):              # the program's own, same name
    def who(self): return "mine"

class Derived(other.Filter): pass

print(Filter().who())              # CPython: mine    pxx: mine
print(Derived().who())             # CPython: other   pxx: MINE
```

It compiled clean and inherited the wrong class. That is the worse failure, it
needs no name collision on the subclass at all, and nothing in the original
report would have found it.

### Same bug, already fixed once, on the other path

`test_nilpy_class_named_after_its_imported_base.npy` covers this exact shape with
a **Pascal unit** and passes — its own header even describes the merge ("the
imported unit's declaration FILLED the forward row NilPy's shell pre-pass had
registered for the program's own class"). The `.py`-module path never got that
fix. Sixth instance of
[[meta-a-second-paths-reimplement-the-first-paths-decisions]], and the first
found by a *previous* fix's leftovers rather than by a new report.

## Fix

Both lookups asked per unit instead of flat: the shell test becomes
`FindUClassInUnit(name, CurrentUnitIdx) < 0`, and `PyParseClass` prefers this
unit's row before falling back to the flat one (the fallback stays for rows the
pre-pass does not cover — a class nested in a body, and compiler-minted shells).

## Verified

Every case diffed against CPython, not against an expectation I wrote:

| case | CPython | pxx |
| --- | --- | --- |
| `class Filter(base.Filter)` (the repro) | `derived` | `derived` |
| `class Filter(other.Filter)`, two modules both with `Filter` | `other` | `other` |
| `class Derived(other.Filter)` + a program `Filter` — the silent one | `mine` / `other` | `mine` / `other` |
| three-level chain `base` → `mid` → program, all named `Filter` (html5lib's shape) | `base` / `mid` / `prog` | same |
| `from mod import Filter`, subclass it, `isinstance` across the boundary | `module` / `sub` / `True` | same |
| the existing Pascal-unit test | unchanged | passes |

The five html5lib filters that reported self-inheritance no longer do; they now
stop on [[bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow]] or on
unrelated missing names (`OrderedDict`, `yield`).

The new test is wired into **both** `test-nilpy` and `test-core`, so it is
covered by the quick tier rather than only by the nilpy suite.

## Gate

The repro prints `derived`; `class Other(base.Filter)` keeps working; a genuine
self-inheritance (`class F(F)`) is still refused — that diagnostic exists for a
reason and must not be traded away for this. Plus `make test-nilpy` green +
self-host fixedpoint.

## Log
- 2026-08-18 — resolved, commit 49c451e97.
