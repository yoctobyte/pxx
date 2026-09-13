---
slug: bug-n-a-module-from-a-guarded-import-gives-one-attribute-int-and-another-variant
title: a module from a guarded import gives one attribute Int32 and another Variant
summary: >
  lekkerzeilen gfx.py:392 -- `annotate the type / too dynamic
  [a=tyInt32(11) b=tyVariant(22)] (inferring least)`. `least = sampling` and
  `least = gl.LINEAR_MIPMAP_LINEAR` disagree, where `gl` came through
  `gl = _backend.gl` and `_backend` is one of two modules chosen by a
  try/except/else import guard. All three constants are plain module-level ints
  in the same file, so the DIFFERENCE is not in the values -- it is in which
  reads of `gl.*` resolve through the alias statically and which fall back to a
  run-time attribute. THE OBVIOUS REDUCTION DOES NOT REPRODUCE (a package
  re-exporting a plain submodule as `gl`, same three constants, same ternary and
  re-assign: compiles and matches CPython), so the guard is load-bearing and the
  reduction has to keep it. This is the lekkerzeilen demo's current wall, the
  fourth cleared today.
track: N
type: bug
prio: 75
owner: unassigned
status: open
---

## The corpus shape

`lekkerzeilen/platform/__init__.py`:

```python
try:
    import ctypes  # noqa: F401
except ImportError:
    from . import _pxx as _backend
    _backend_name = "pxx"
else:
    from . import _ctypes_backend as _backend
    _backend_name = "ctypes"

gl = _backend.gl
```

`lekkerzeilen/gfx.py:389`:

```python
sampling = gl.LINEAR if smooth else gl.NEAREST
least = sampling
if levels and smooth:
    least = gl.LINEAR_MIPMAP_LINEAR          # <- refused here
```

`LINEAR`, `NEAREST` and `LINEAR_MIPMAP_LINEAR` are all `X = 0x....` at module
level in `platform/_gl.py`. Nothing about the three differs.

## What was measured, 2026-09-13

- The error names `least`, with `a=tyInt32` and `b=tyVariant`. So one of the two
  assignments produced a static int and the other a run-time variant.
- **A reduction WITHOUT the import guard compiles and matches CPython.** A
  package whose `__init__` does `from . import mod as gl`, `mod` holding the
  same three constants, through the same ternary-then-reassign: pxx prints
  `(9987, 9729)` / `(9728, 9728)`, identical to CPython. Recorded because it is
  the useful half of a null result — it rules out the ternary, the re-assign,
  the constants and plain module re-export, and points the next reduction at the
  GUARD.

## Where to look, and the neighbours that make it likely

CLAUDE.md records a measured finding in exactly this machinery: the unit-alias
table binds the DEAD arm of a guarded import, **and only when an `else:` puts
the live arm after the handler** — in the no-`else` idiom the live arm is
lexically first in both outcomes and wins by position. This seam has the `else:`,
and its own comment says the `else` is load-bearing and was rewritten for the pxx
demo on 2026-09-11.

So the first hypothesis to test is that `_backend` is aliased to `_pxx` (the dead
arm on this host, and a 39-line NotImplementedError stub) for SOME lookups and to
`_ctypes_backend` for others — which would explain an attribute resolving
statically through one and dynamically through the other, in one expression.

`PXXDBG=n.locals` on gfx.py's `_configure` (or whichever routine holds line 389)
names what the frontend inferred, which is cheaper than reasoning about it.

## Not the same as

`bug-n-a-callable-attribute-dispatched-at-run-time-takes-at-most-4-arguments` and
the dynamic-dispatch arity work cleared the wall 7 lines earlier (gfx.py:385).
That was a frontend cap; this is an inference disagreement, and the two are
unrelated beyond sitting in the same routine.
