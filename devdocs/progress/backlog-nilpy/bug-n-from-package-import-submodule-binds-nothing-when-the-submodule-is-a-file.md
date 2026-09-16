---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`from .platform import _gl` binds nothing when _gl is a SUBMODULE reached by its own filename: a member access on it errors `no member <x> came of the qualifier _gl`. `from . import <module>` and `from .platform import gl` (gl a NAME assigned in platform/__init__.py) both work; only the file-named submodule form fails, with or without `as`. Found by the lekkerzeilen seat; consequence is that lekkerzeilen/platform/* is uncoverable by a generated value sweep."
status: open
---

# `from .package import <submodule-file>` binds nothing

Reported by the lekkerzeilen seat, 2026-09-16, two-line repro that fails in
~10 s:

```python
from .platform import _gl
print("plain %r" % (_gl.core_loaded(),))
# -> pascal26:2: error: no member core_loaded came of the qualifier _gl
```

## What works and what does not

- `from . import <module>` — works.
- `from .platform import gl` where `gl` is a NAME assigned in
  `platform/__init__.py` (line 86 in the demo) — works.
- `from .platform import _gl` where `_gl` is a SUBMODULE, i.e. the file
  `platform/_gl.py`, reached by its own filename — binds nothing, with or
  without `as`. A later member access errors `no member <x> came of the
  qualifier _gl`.

So the resolver handles a re-exported NAME from a package `__init__` but not a
SUBMODULE named directly in a `from .package import` statement. The
distinguishing axis is name-in-`__init__` vs file-on-disk, not the relative
dots (both forms above are relative).

## Why it matters

The lekkerzeilen demo compiles only because it uses the two working forms.
But `lekkerzeilen/platform/*` is then uncoverable by a generated value sweep
(the seat's lexical-order / generated-row instruments), and `platform/_pxx.py`
does not parse under CPython `ast` either, so that layer is dark from both
ends. This is a coverage-enabling fix, not a demo blocker.

## Where to look

The NilPy import binder in `pyparser.inc` (PyPreScanImports /
FindUnitOrAlias / the `from ... import` handling). The working NAME case
suggests the binder resolves an imported symbol against the package's own
declared names but does not fall through to "the name is a submodule file of
the package" — the same resolution `import package.submodule` must already do.
Normalise the two rather than add a third path
(devdocs/dev/normalise-dont-special-case.md).

## Positive control

The repro above errors on the current compiler and must COMPILE and print
`plain <result>` when fixed. Re-derive the expected value from the built
thing rather than from this ticket (the member's return type is not asserted
here).
