---
slug: bug-n-a-dynamically-dispatched-call-fills-its-defaults-from-another-class-signature
title: a dynamically dispatched call fills its parameter defaults from another class's signature
summary: >
  `g.at(a, b)` on a receiver with no static type dispatches to the right class
  at run time but takes its PARAMETER DEFAULTS from whichever same-named method
  the candidate scan saw first -- which, when the receiver's class lives in a
  module parsed later, is a sibling class in the CALLER's own module. Measured:
  a call that CPython answers `outside=None` answers `outside=0.0`, where 0.0
  is the default of a differently-named parameter of a different class. No
  warning. When the two signatures also differ in LENGTH the call is built with
  the wrong argument count, the run-time bind fails, and a variant tagged
  VT_OBJECT with payload 1 is returned instead -- no method body runs and there
  is no diagnostic. That is lekkerzeilen's world-path fault (wind.py:143).
track: N
type: bug
prio: 88
owner: frank-user
status: open
---

## Repro

Three files, 40 lines, in `devdocs/progress/repro/dynamic-default-signature/`
and reproduced inline here. The shape is the one lekkerzeilen has and a
single-file reduction does NOT have: the class that declares the method is in a
module parsed AFTER the caller, and the caller's own module declares a
same-named method with a different signature.

`pkg/early.py` -- imports nothing, exactly like `lekkerzeilen/wind.py`:

```python
class Breeze:
    def at(self, x, z, t=0.0, height=6.0):        # the sibling signature
        return "Breeze.at ..."


class Sampler:
    def __init__(self, grid=None):
        self.grid = grid

    def march(self, a, b):
        g = self.grid                              # no static type
        if g is None:
            return "no grid"
        return g.at(a, b)
```

`pkg/late.py`:

```python
class Grid:
    def at(self, x, z, outside=None):
        return "Grid.at x=%r z=%r outside=%r" % (x, z, outside)
```

`pkg/__main__.py` imports `early` first, then `late`, and calls
`Sampler(Grid()).march(1, 2)`.

| row | CPython | pxx @ ee441baba |
| --- | --- | --- |
| `g.at(1, 2)`, name shared with a sibling class | `outside=None` | **`outside=0.0`** |
| `g.sample_zzz(1, 2)`, name unique to `Grid` | `outside=None` | **TypeError, see below** |

The second row is the same defect with no sibling to mis-read: the scan finds
nothing, falls to the run-time lookup, and the run-time lookup applies no
defaults at all --

    TypeError: sample_zzz() missing positional argument(s):
               its parameter list holds 3 and only 2 could be bound

## The three outcomes, one cause

Which one you get depends only on what the scan happens to see, which is why
this has been so hard to corner -- two of the three are harmless:

1. **No candidate visible, no defaults needed** -- falls to the run-time lookup
   and is CORRECT. `canopy.contains(sx, sz)` takes this arm and returns the
   right answer, while the build log says "no class declares .contains()" and
   five classes do.
2. **No candidate visible, a default needed** -- run-time lookup, hard error.
   Loud, and the message names the arity honestly.
3. **The WRONG candidate visible** -- never reaches the run-time lookup. Static
   signature, wrong defaults, silent wrong value. This is the one that hurts.

## Where it bites in lekkerzeilen

`wind.py:143`, `rise = canopy.at(sx, sz) - self.level`. `wind.py` imports
nothing and `__main__.py` takes `from .wind import Wind` at line 207 and
`from . import world as world_mod` at line 325, so when `Wind.shelter`'s body
is parsed the only visible `.at` is `Wind.at(self, x, z, t=0.0, height=6.0)`
-- forty lines above the call, in the same file. Its signature holds four
parameters; `TiledGrid.at(self, x, z, outside=None)` accepts three.

Measured with entry prints in every one of the six classes declaring `.at`
(Grid, TiledGrid, Route, Wind, ui, gauges): on the failing call **none of them
is entered**, and the call still returns a value. Under gdb the fault is

    main -> App.run -> Environment.wind -> Wind.at -> Wind.shelter
         -> pysub_v -> PyVarUserArith -> PyVarUserObj -> mov (%rax),%rax, rax=1

with the operand variant `{VType = 7, Payload = 1}` -- si_addr 0x1, si_code 1.
Exactly one such variant per run.

## Why no reduction found it

Two single-file reductions came back CLEAN before this one: a method with a
defaulted parameter on a variant receiver (7 rows), and the same with the
caller parsed before the class (3 rows). Both test the SHAPE, and the shape is
fine -- a parser pass sees every class in one file. Only the cross-MODULE
arrangement, with a sibling of the same name in the caller's module, reproduces
it. See debugging-playbook.md.

## Where to look

`compiler/pyparser.inc:19256`, the candidate scan. It keeps a first-wins static
pick plus up to sixteen run-time is-test arms, and the pick supplies the
SIGNATURE -- arity and defaults -- for a call that will dispatch elsewhere.
The same machinery already has a lekkerzeilen casualty recorded in its own
comment at :19524 (`app.py:1678`, `tile.grids.pop(name, None)`, first-wins
picked TPyDeque). There the wrong pick produced a loud error; here it produces
a wrong value.

Note that four pylib containers -- TPyList, TPyBytes, TPyRange, TPyDeque --
each declare `at(i)` taking ONE argument, so `.at` is a name the scan always
has candidates for.

## Gate

`make test-nilpy` + self-host byte-identical, plus a multi-module fixture under
`test/nilpy_units/`. Both rows above belong in it: the silent wrong default and
the loud missing one, because a fix that only taught the run-time lookup to
apply defaults leaves row 1 silently wrong.

## Log
- 2026-09-14 -- diagnosed from the lekkerzeilen world-path segfault: live gdb
  for the location, a probe runtime that reports instead of dereferencing for
  the value, entry prints in all six candidates to prove no body runs, then
  three reductions to find the arrangement. Filed with the repro.

## Three things measured AFTER filing, each of which narrows the fix

**1. The run-time lookup CANNOT be taught defaults without new RTTI.**
`TMethInfo` (lib/rtl/typinfo.pas:71) carries `NamePtr`, `Code`, `Arity`,
`RetKind`, `ParamKinds` (kinds, then param-name pointers) and `Flags`. There is
no block of DEFAULT VALUES. So the honest error in row 2 is not an oversight in
PyHostCall -- the information is not there to bind with. Giving the dynamic path
defaults is a FEATURE touching the RTTI emitter and that mirror record, not a
fix, and it would still leave row 1 wrong.

**2. The ordering fix is the one that repairs all three outcomes, and it is
already proven.** Swapping the two import lines in the repro's `__main__.py`
turns both rows correct. `PyPreScanImports` (pyparser.inc:42740) does visit
every import token including function-local ones -- its own header says it has
no notion of reachability and resolves them all -- but it walks them in TOKEN
ORDER, and `PyParseImportUnitAs` (:41942) parses a pulled module's BODIES at
pull time. So wind.py's bodies are parsed during the prescan, before world.py
is mentioned at all. The repair is a two-phase pull: register every imported
module's class shells first, then parse bodies. That is a restructure of shared
import machinery with a long tail of documented prior bugs (guarded arms,
soft misses, alias rollback) and it is NOT a small change.

**3. THE OBVIOUS WORKAROUND DOES NOT WORK -- do not ship it.** Adding
`from . import world` to the top of `lekkerzeilen/wind.py`, with every other
source byte-identical to the owner's tree, MOVES the failure rather than
removing it: the world path then dies during startup with

    AttributeError: 'World' object has no attribute 'flow'

and `World` does declare `flow`, as a @property (world.py, the `grid`/`bed`/
`canopy`/`flow` block). So either the same family bites one layer over on a
property lookup, or perturbing the module graph reorders some other first-wins
pick. Either way the world path does not run, and "one-line workaround" must
not travel as a fact. Measured twice, the second time on otherwise-pristine
sources.
