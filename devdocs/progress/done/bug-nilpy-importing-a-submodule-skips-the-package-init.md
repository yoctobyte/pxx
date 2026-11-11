---
track: N
prio: 50
type: bug
status: done
---

# `import pkg.sub.mod` does not run pkg/__init__.py

Found 2026-10-20 while testing `__name__`. With `pkg/__init__.py` printing a
line, CPython prints it before `pkg/sub/mod.py`'s output; pxx skips it. Seen on
HEAD before the `__name__` change too. Anything a package's `__init__` sets up
(module-level state, re-exports with side effects) is missing.

## Fixed 2026-11-11

PyImportPackageParents (pyparser.inc), called from PyParseImportUnitAs: before
an absolute dotted import, each prefix that has an `__init__` on disk under the
absolute-import roots is imported first, exactly as `import <prefix>` would be.
So pkg/__init__ runs before pkg/sub/mod, and `pkg` is bound: `pkg.TOP` after
`import pkg.mod` now works (it was "undefined variable (pkg)"). A prefix with
no `__init__` (a namespace package, or a dotted name a shim answers such as
`xml.dom.minidom`) is skipped. Relative imports are not touched; their parents
are the importing package itself.

Two neighbours fixed in the same visit, found with the same fixture:

- `from .inner.leaf import val` (relative, dotted module) probed
  `<dir>/inner_leaf.py` and failed with "no unit named inner_leaf". The
  relative probe in ResolveUsesUnitSource now uses the dotted path.
- `from pkg.inner import leaf`, after pkg/inner/__init__ did
  `from .leaf import val`, bound nothing. The file was compiled under the bare
  name `leaf`, the absolute spelling added `pkg_inner_leaf -> leaf`, and the
  binding added `leaf -> pkg_inner_leaf`: a cycle in the alias table.
  PyAddImportUnitAlias now stores the resolved unit and skips a self-alias.

What stays different: pxx runs ALL of a module's imports before its own first
statement (the unit model), so with prints in every module the order is
`pkg init, leaf, inner init, mod` where CPython prints
`pkg init, mod, inner init, leaf`. Written up in
devdocs/dev/nilpy-semantics-divergences.md.

Test test_nilpy_package_parents_init_first.py (row pkgparent26), fixture
test/nilpy_pkginit26, expected = python3.
