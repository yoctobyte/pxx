---
slug: bug-n-a-dynamically-dispatched-call-fills-its-defaults-from-another-class-signature
title: a dynamically dispatched call fills its parameter defaults from another class's signature
summary: >
  FIXED 2026-09-14 (the "FIXED -- two halves" section below) AND RE-MEASURED AT
  HEAD 2026-09-19: the committed reduction in
  devdocs/progress/repro/dynamic-default-signature/ now matches CPython BYTE FOR
  BYTE on both rows -- the shared-name row and the unique-name row -- so this
  ticket is DONE and is being closed. It sat open at prio 88, the highest open
  number under its umbrella, for five days with its own body recording the fix,
  and a seat was dispatched to it on the strength of this summary. Read the rest
  as the 2026-09-14 report it was.

  WHAT IT WAS: `g.at(a, b)` on a receiver with no static type dispatched to the
  right class at run time but took its PARAMETER DEFAULTS from whichever
  same-named method the candidate scan saw first -- a sibling class in the
  CALLER's own module when the receiver's class lived in a module parsed later.
  A call CPython answers `outside=None` answered `outside=0.0`, with no warning.

  STILL OPEN, and NOT this ticket: the lekkerzeilen world path still does not
  run. It gets further and then dies in `malloc(): unsorted double linked list
  corrupted` -- heap corruption, a different defect. See also
  bug-n-a-run-time-dispatched-call-s-result-is-coerced-to-an-integer, which this
  fix UNCOVERED and which has its own repro.
track: N
type: bug
prio: 88
owner: frank-user
status: done
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

**3. THE OBVIOUS WORKAROUND FIXES THIS SITE AND UNCOVERS THE NEXT ONE.** Adding
`from . import world` to the top of `lekkerzeilen/wind.py`, with every other
source byte-identical to the owner's tree, MOVES the failure rather than
removing it: the world path then dies during startup with

    AttributeError: 'World' object has no attribute 'flow'

and `World` does declare `flow`, as a @property (world.py:1272; `Region.flow`
at :343 is a second, and `Environment.flow` at environment.py:25 is a plain
instance attribute -- three unrelated declarers).

CORRECTED by lekkerzeilen-c8, who ran the test in both spellings, 3/3 each,
before my "do not run it" reached them:

  A. `from . import world` added to wind.py
  B. `from . import world` at module level in __main__.py, ahead of
     `from .wind import Wind` -- adds NO new import edge to wind.py, it only
     changes what the scan has seen when wind.py is parsed

Both give rc=217 with the identical message, and both turn an unattributable
segfault 2.95s into the frame loop into a NAMED deterministic error at 0.95s.
Spelling B is what retires the "perturbed module graph" worry: the graph is
unchanged and the answer is the same to two decimal places.

So the workaround is not a failure -- it repairs `.at` and then falls into the
SECOND INSTANCE of this same defect, on a property read. `app.py:1243`,
`self.env.flow = source.flow if source else None`, where `source = self.scene`
is a Region OR a World. The message is FALSE as stated: the property is there.

**This is why an app-side import order cannot be the fix.** `.at` and `.flow`
want different orders, so there is no single arrangement that satisfies both;
the repair has to be in the compiler.

**AND THE WARNING'S ABSENCE IS NOT EVIDENCE OF SAFETY -- read a build log the
other way round.** `.up`, `.water_level` and `.spawn` all draw "several
unrelated classes declare a .X property"; `.flow`, with three declarers, draws
NOTHING. Identical to `.at` (silent, three declarers) against `.contains`
(warned, five declarers). Where the scan sees the WRONG SUBSET it stays quiet
and binds anyway; where it sees nothing it says so. A reader scanning warnings
for trouble is looking at exactly the sites that are fine.

## FIXED 2026-09-14 -- two halves, and neither works alone

**1. THE FRONTEND: the closed world's innermost fallback is now the open world.**
`PyParseVariantMethod` builds a chain of runtime-tested arms over a STATIC arm,
and that static arm -- `hitCi`, the first-wins pick -- was the innermost
fallback. A receiver that matched no arm therefore took a VMT-slot call on a
class it is not, with `hitCi`'s DEFAULTS already filled at the call site. It is
now wrapped:

    pyvarobj(recv) is <the pick> ? <static call> : pydyn_meth<n>(recv, 'name', ...)

Pascal's `is` is true for the pick and every descendant, so nothing the static
arm was right about changes; only a genuinely unrelated class falls through,
and today that class gets a wrong-slot call. **Narrowed to `i + 1 <
ParamCount`** -- calls where the site FABRICATES arguments from a guessed
signature, which is the defect's actual mechanism rather than its
neighbourhood. A call whose arity matches exactly is untouched.

**2. THE RUNTIME: the by-name binder can now fill the callee's OWN defaults.**
This is what made the first half insufficient on its own -- routed to
`pydyn_meth2`, the reduction then died with `at() missing positional
argument(s)`, because `PyHostCall` had `mi^.Arity` and no values. The defaults
already existed, populated, in the PYSIG record `EmitPySignatures` emits per
def; there was simply no route from a TMethInfo to one (`Code` is a code
address and keys nothing).

The route is ONE WORD, appended to the method's ParamKinds block after the
name pointers, flagged by `RTTI_METH_FLAG_HASSIG`. In the BLOCK and not in the
record, for the same reason the `*args` index lives in Flags: TMethInfo's
mirror in `lib/rtl/typinfo.pas` and the three stride consumers must not move
(project_rtti_method_table_multi_consumer_stride_landmine). The block carries
no length word, so every reader that takes `Arity` kinds and `Arity` names
cannot see it. `pysig_fill_defaults` lives in pylib, which already owns the
layout, so pyeval passes the pointer and never learns the shape -- a third
mirror is a third thing to keep in step.

It is **all-or-nothing**: every slot in the missing range is checked before any
is appended, because a partial fill calls the body at an arity it cannot take,
which is the smash this path exists to stop. When it declines, the existing
TypeError still fires and still says the true thing.

Reduction: `devdocs/progress/repro/dynamic-default-signature/` now matches
CPython byte for byte on both rows. Fixture:
`test/test_nilpy_dynamic_call_takes_defaults_from_its_own_class.npy`, whose
package puts the fitting class SECOND -- the only arrangement a first-wins
table is exposed by -- and whose control rows (a call written in full, and a
receiver that really IS the pick) assert that the static arm still wins where
it was already right.

## What this did NOT fix, measured rather than assumed

**The world path still does not run.** It gets FURTHER -- the `.at` site is
repaired and the run advances from ~2.95s in-loop to ~5.7s -- and then dies in
`malloc(): unsorted double linked list corrupted`, a HEAP corruption, which is
a different defect wearing a different failure mode. `--open-water` survives a
150s timeout (rc=124) on the same binary, so the corruption is specific to the
world path and not general.

**And one layer underneath was uncovered:**
`bug-n-a-run-time-dispatched-call-s-result-is-coerced-to-an-integer` -- a
dispatched call returning a float truncates and one returning a string raises.
Filed with its own repro and a control proving it was UNREACHABLE before this
fix, because the call never completed at all.

- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 92136431f.
