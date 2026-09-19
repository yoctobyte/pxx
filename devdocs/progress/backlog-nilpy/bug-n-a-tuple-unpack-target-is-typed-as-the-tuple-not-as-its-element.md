---
slug: bug-n-a-tuple-unpack-target-is-typed-as-the-tuple-not-as-its-element
title: a tuple-unpack target is typed as the tuple, not as its element
summary: >
  `v, b = g.values, g.base` gives every target the RHS TUPLE's type (TPyList)
  instead of the element's, so a name whose single-assignment spelling types
  correctly is statically a list. The handle at run time is still the real
  object, so values are right and `type(v).__name__` is not -- it answers
  CPython's `array` with `list`. The class of bug is a target typed as the
  CONTAINER a multi-assignment builds; it springs wherever an unpack RHS is
  heterogeneous or its elements have a class the receiver already knows.
  A WRONG type also costs more than no type: an inference fix upstream that
  makes the field resolve turns the lekkerzeilen chart 5x SLOWER, because the
  unpack then feeds a wrong class where it used to feed a variant.
track: N
type: bug
prio: 55
owner: frankh-c0
status: open
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
