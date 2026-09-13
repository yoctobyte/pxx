---
slug: bug-n-a-module-from-a-guarded-import-gives-one-attribute-int-and-another-variant
title: nine of the eleven machine integer kinds had no join in PyWiden
summary: >
  lekkerzeilen gfx.py:392 -- `annotate the type / too dynamic
  [a=tyInt32(11) b=tyVariant(22)] (inferring least)`. THE TITLE AND THE
  HYPOTHESIS BELOW ARE WRONG and are kept as the record of how this was found:
  the guarded import is not load-bearing, the ternary is not, the enclosing `if`
  is not, and `gl` is bound to the arm the host actually selects. The mechanism
  is that `PyNumeric` -- the membership test `PyWiden`'s numeric arm and
  `PyVariantScalar` are both built on -- listed tyInteger and tyInt64 and nothing
  else, so tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32, tyUInt32, tyUInt64,
  tyNativeInt and tyNativeUInt reached no arm of the join at all and fell out of
  its bottom. `gl.LINEAR` is a C `int` constant and so arrives as tyInt32;
  `gl.LINEAR_MIPMAP_LINEAR` is genuinely absent from the pxx backend's `gl`
  class and so reads as a run-time attribute, tyVariant; tyInt32 had no join with
  a variant, with an Int64, or with a Double. Fixed: PyNumeric is the full
  integer set (symtab.inc's TypeIsPyNumeric has held it all along -- two
  mechanisms for one concept, the narrow one wired into the join), and any float
  side of the numeric arm now answers tyDouble. THE LEKKERZEILEN DEMO COMPILES
  AND RUNS as a result.
track: N
type: bug
prio: 75
owner: frankH
status: done
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


## RESOLVED 2026-09-13 — and the hypothesis above was wrong

Everything from "Where to look" up is the record of a wrong hypothesis, kept
because the null reductions in it are still true statements and because this
ticket is what a later reader will find first.

**The guard is not load-bearing. Neither is the ternary, nor the enclosing `if`.**
The reduction that settles it has none of the three and refuses identically:

```python
from lekkerzeilen.platform import gl
def f(smooth, levels):
    least = gl.NEAREST
    least = gl.LINEAR_MIPMAP_LINEAR
    return least
```

and the sharpest one needs no lekkerzeilen at all — a Pascal unit with
`function ret32: LongInt`:

```python
import 'u.pas' as u
y = 1.5
y = u.ret32()     # annotate the type / too dynamic [a=tyDouble(19) b=tyInt32(11)]
```

**The mechanism.** `PyNumeric` (pyparser.inc) listed `tyInteger` and `tyInt64`.
`PyWiden`'s numeric arm and `PyVariantScalar` are both built on it, so every
other machine integer kind matched no arm and fell out of the function's bottom
into `Error(PyWidenErr)`. Measured per kind, one Pascal unit returning each,
against `y = 0; y = k.r_<kind>()`:

| kind | before |
| --- | --- |
| tyInt8(7), tyUInt8(8), tyInt16(9), tyUInt16(10) | refused |
| tyInt32(11), tyUInt32(12) | refused |
| tyUInt64(14), tyNativeInt(15), tyNativeUInt(16) | refused |
| tyInteger(1), tyInt64(13) | compiled |

That table is the fixture's positive control.

**Why the two reads differ, which the title got backwards.** `gl.LINEAR` is a C
`int` constant reaching NilPy as tyInt32 — nothing exotic, just the width the
callee declared. `gl.LINEAR_MIPMAP_LINEAR` is **absent** from the pxx backend's
`class gl` (`lekkerzeilen/platform/_pxx.py` has `LINEAR` and `NEAREST` and not
that one), so it is read as a run-time attribute and typed tyVariant. Both
answers are correct about their own read; the defect was that no join existed
between them. The missing constant is lekkerzeilen's own gap and the demo runs
without it — that branch needs `levels and smooth`.

**Fixed** in `fec1abd13`: `PyIntKind` is the full machine-integer set and
`PyNumeric` is `PyIntKind or TypeIsFloat`; the integer join answers tyInt64, or
tyPromoInt64 when a kind whose top bit overflows one is involved; and any float
side answers tyDouble (the old test named only tyDouble/tyExtended, so
tySingle-meets-integer answered an INTEGER kind and dropped the fraction).
`symtab.inc`'s `TypeIsPyNumeric` has held the complete list since it was written
— two mechanisms for one concept, with the narrow one wired into the join.

Test: `test_nilpy_pascal_integer_widths_join.npy` +
`test/nilpy_units/intwidths.pas`, `.expected` from CPython.

**The lekkerzeilen demo now compiles and runs.** `ok: bin/lz_h1 [code=12504744B
procs=11711]`, warnings only; it brings up the GL context (3.3.0 NVIDIA), loads
the world (`rijn: 4 tiles, 1 pounds, 5 routes`) and prints the key legend before
the next wall, a run-time `forwarded call got 5 arguments, expected 0 to 4`.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
