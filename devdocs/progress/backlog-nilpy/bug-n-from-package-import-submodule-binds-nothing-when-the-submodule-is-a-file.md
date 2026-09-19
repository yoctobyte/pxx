---
track: N
prio: 40
type: bug
blocked-by: []
summary: "MECHANISM (re-measured 2026-09-19 at 2bfcfa8bf23e, and it is an ANCHORING bug, not a spelling one): `from .pkg import <submodule-file>` resolves only when the package directory is itself a search root. The submodule arm now exists and finds the file -- strace shows `<root>/P/platform/_gl.py` opened -- and then the unit resolver probes the MANGLED key beside the importer and the DOTTED path under the -Fu ROOTS, so a package one level below a root is never reached. A main script INSIDE the package works; a module of the package driven from outside gives `no unit named platform__gl`. Fix: derive the package dotted path from the root that contains it. Same anchoring question as bug-n-a-subpackage-directory-does-not-resolve-as-a-module (p55) -- do them together."
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

# 2026-09-19, frankH -- half of this is fixed; what is left is the SEARCH ROOT, not the spelling

At compiler 2bfcfa8bf23e the submodule arm exists (the absolute twin of this
ticket, bug-n-from-a-package-import-a-submodule-binds-nothing, is closed) and
a zero-byte `__init__.py` resolves. `from .platform import _gl` now WORKS when
the importing file is a main script sitting in the package directory: probe
`P/{__init__.py, platform/{__init__.py,_gl.py}, main_inside.npy}` prints 7.

It still fails when the importer is a MODULE of the package reached through a
`-Fu` root above the package: `P/mod.py` with the same statement, driven by an
outside `from P.mod import go`, gives

    import: no unit named platform__gl and no shim mimic_platform__gl

and that is the whole residual. Measured with strace, which names the cause
exactly: the correct file IS found by the arm's own probe
(`<root>/P/platform/_gl.py`, opened, fd 3 -- that is PyPackageSubmoduleKey
answering), and then the unit resolver looks for the MANGLED key
`<root>/P/platform__gl.py` beside the importer and for the DOTTED path
`platform/_gl.py` under the roots -- i.e. under `<root>`, never under
`<root>/P`. The dotted path is anchored at a search root while the package is
one level below it.

So the fix is to hand the resolver the package's path from a ROOT (derive the
dotted name by matching the package directory against PasUnitDirs, then join
the submodule) rather than the bare `<pkg>.<sub>`. Not attempted here: this
ticket's other rows are closed, and the remaining one is the same anchoring
question as
bug-n-a-subpackage-directory-does-not-resolve-as-a-module (p55), whose
`from .platform.gl import area` row fails identically on HEAD and on pin v411.
Worth doing the two together.
