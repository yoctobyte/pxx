---
slug: bug-n-a-tuple-unpack-target-is-typed-as-the-tuple-not-as-its-element
title: a tuple-unpack target is typed as the tuple, not as its element
summary: >
  FIXED (fix(N), this ticket's commit). MECHANISM: PyParseUnpackAssign ran EVERY
  unpacked value through PyDrainIfCursor, which materialises anything declaring
  `__iter__` into a TPyList. That is right for `a, b, c = bag` -- one value
  INDEXED into several targets -- and wrong for a value per target, where
  nothing is indexed and the value must be stored as it stands. The target was
  therefore typed from the list the drain built, not from its own value. It
  springs for ANY unpack target holding a shim or user-defined iterable, not
  only array: the condition is the class declaring `__iter__` and the unpack
  being parallel. The drain now runs only when nValues = 1 and nTargets > 1.
track: N
type: bug
prio: 55
owner: frankH
status: done
---

## Reproduce

`scratchpad/mb/tup2.py`, compiler 69f58043de11, oracle CPython 3:

```python
import array


class G:
    def __init__(self):
        self.values = array.array("h")
        self.values.frombytes(bytes(8))
        self.base = 5


def f(g: G):
    single = g.values
    v, b = g.values, g.base
    print(single[0], v[0], b)
    print(type(single).__name__, type(v).__name__)


f(G())
```

pxx prints `array_ list`; CPython prints `array array`. The value rows agree.

`PXXDBG=n.locals` on the same file:

```
f single tk=6 rec=145      { array_ }
f v      tk=6 rec=35       { TPyList }
f b      tk=13 rec=-1      { Int64, correct }
```

So `single` is typed from the field (0664366e7, which taught the pre-pass the
qualified shim constructor) and `v` is typed from the list the unpack builds.

## Why the cost is not symmetric with "untyped"

Measured on lekkerzeilen 01d0fec plus the `chart_view` workaround, driver
`scratchpad/lz/lekkerzeilen/chartbench.py` (Tiles + Chart at the world spawn,
no window, no GL), min of 5, `--threadsafe`, check row `137505351 786432`
identical in every arm:

| chart.py `_sound` | bench |
| --- | --- |
| `grid` unannotated (`values` is a variant) | 3.40 s |
| `from . import world` added, still unannotated | 3.55 s |
| `grid: world.Grid` (`values` resolves, unpack types it `list`) | 16.85 s |

CPython on the same driver: 0.42 s total.

`_sound` line 131 is `values, base = grid.values, grid.base`, which is why the
annotation reaches this bug rather than helping. The import arm is there
because an annotation naming a module chart.py does not import is accepted
SILENTLY by pxx (CPython raises NameError at def time, since a bare annotation
is evaluated) -- that is a second, smaller divergence and it is what produced a
misleading first measurement here.

## What would retire this row

The table's third row dropping to at or below the first. The type-name row is
the cheap oracle check and does not need the app.

## Resolution (frankH, 2026-09-20)

Fixed in PyParseUnpackAssign: the values are parsed into `vals[]` first and the
temps allocated after, so `PyDrainIfCursor` can be applied to the single value
ONLY in the one-value-many-targets arm. Each target then takes its own value's
type kind and class identity, which the parallel store already forwarded
correctly -- the builder was never wrong, the value handed to it had been
replaced before it got there.

Diagnosed by printing rather than reading: a probe in the temp loop reported the
value arriving as `kind=8` (AN_CALL) with `rec=TPyList`, which is the drain call,
not the field read. The symbol came out of the store with that same rec, so every
later resolution against it saw a list.

Fixture `test/test_nilpy_a_tuple_unpack_target_keeps_its_own_class.npy`, wired
into test-nilpy. It covers the fix and the three shapes that must NOT change:
the drained `w, h = "3x4".split("x")`, a plain list source, and a cursor in a
parallel position (`it, n = gen(), 9`, still summable). `.expected` derived from
CPython 3.14.4. Positive control on stable_linux_amd64/default/pinned:
`AttributeError: 'TPyList' object has no attribute 'typecode'`.
Full test-nilpy GREEN at compiler ce5ab1cb5f92 (same sha printed before the run
and after it). gate.sh quick GREEN, after one AST slot-write snapshot row that
the rename produced (`tmps[nValues]` -> `tmps[i]`, plus the new `vals[i]`): both
are ordinary node writes, reviewed and taken with --update.

### The second item does NOT reproduce as stated, and the oracle is why

This ticket's note says an annotation naming a module the file does not import
is "accepted SILENTLY by pxx (CPython raises NameError at def time)". Measured
today, at HEAD, both halves fail:

- pxx is NOT silent. `def use(grid: world.Grid)` in a module that never imports
  `world` prints `warning: Nil Python: parameter grid has a type annotation this
  frontend cannot read; treating it as Any` -- twice -- and types the parameter
  Any. Tried with the module reachable as a sibling in the same package, and
  with another module in that package having done `from . import world` first.
- CPython does not raise on this box. `python3` here is **3.14.4**, where PEP 649
  defers annotation evaluation, so the un-imported annotation is never evaluated
  at def time and the program prints the same answer pxx does. The NameError
  claim is true for CPython <= 3.13 and there is no such interpreter installed
  (`/usr/bin/python3.14` is the only one).

SETTLED (frankb-8e, same day): there is NO residual divergence. The resolving
arm exists and is the 16.85 s row, where chart.py DOES import world -- so the
annotation resolving there is correct behaviour, not silent acceptance. The
shape described in the note was a fourth arm, measured first and then dropped:
annotation with no import, degraded to Any, 3.407 s, i.e. the unannotated
timing, because in effect it is unannotated. The table's conclusion stands on
the resolving row. Not filed as a ticket, because the mechanism as stated does
not happen.

## Log
- 2026-09-20 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 47841c55b.
