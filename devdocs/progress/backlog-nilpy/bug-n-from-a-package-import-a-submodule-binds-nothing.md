---
slug: bug-n-from-a-package-import-a-submodule-binds-nothing
title: from a package import a submodule binds nothing
summary: >
  `from pkg import sub`, where `sub` is a MODULE in the package rather than a
  name in its `__init__.py`, binds nothing: the first use fails at COMPILE time
  with "no member area came of the qualifier geo". Both `import pkg.sub as sub`
  and `from pkg.sub import name` work, and so does the RELATIVE spelling
  `from . import sub` -- which is the same statement with the package named
  implicitly, and which already has the machinery (PyParseRelImportNames, "the
  names ARE the modules"). So this is one absolute arm that never learned what
  its relative twin knows. Loud, not silent.
track: N
type: bug
prio: 45
owner: unassigned
status: open
---

## Measured 2026-09-13 (frankH), at 17eaf7f74

Package `mypkg/` with `__init__.py` holding `NAME = "mypkg"` and `geo.py`
holding `def area(w, h)` and `SCALE = 3`. Five spellings, CPython answers on
the left:

| spelling | CPython | pxx |
| --- | --- | --- |
| `from mypkg import geo` | 6 | **compile error** |
| `from mypkg import geo as g` | 6 | **compile error** |
| `from mypkg import NAME` | mypkg | mypkg |
| `from mypkg.geo import area` | 6 | 6 |
| `import mypkg.geo as geo` | 6 | 6 |

The error names the qualifier and is helpful about the class of cause:

    pascal26:3: error: no member area came of the qualifier geo — check what
    geo resolves to; an import that bound nothing gives exactly this

**Importing the module FIRST does not help**: `import mypkg.geo` followed by
`from mypkg import geo` still fails, so the submodule being already compiled and
in the unit table is not what the arm is missing -- it never tries to bind the
name to a unit at all.

## Where the fix goes

`PyParseRelImportNames` (pyparser.inc) is the relative arm and its own header
states the rule this bug is the absolute half of: *"`from . import a, b` -- the
names ARE the modules"*. It calls `PyParseImportUnit(name)` and then
`PyBindImportUnitAlias(name)`. The absolute arm in `PyParseImportRun` treats
every name after `import` as a MEMBER of the named module and has no fallback to
"...or a submodule of it".

The shape of the fix is therefore: for each name in an absolute from-import,
when it does not resolve as a member, try `<impName>.<name>` as a module and, if
that resolves, register the unit alias `<name> -> <impName>.<name>` -- which is
exactly what `import pkg.sub as sub` already does and what the relative arm
already does.

## Why it is prio 45 and not higher

It is LOUD -- a compile error at the first use, naming the qualifier -- and two
spellings of the same intent work today, so no program is silently wrong. It is
ranked on how ordinary the spelling is rather than on severity: `from pkg import
sub` is the form most Python code writes, and lekkerzeilen only avoids it by
being inside its own package (`from . import geometry`), which takes the arm
that works. Found from outside, writing a four-line probe against the demo's own
`geometry` module.
