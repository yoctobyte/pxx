---
slug: bug-n-traffic-py-has-an-uninferable-heading-field
title: lekkerzeilen/traffic.py — self.heading has no inferable type
track: N
type: bug
prio: 60
status: open
summary: >
  lekkerzeilen/traffic.py refuses with `cannot infer the type of field
  self.heading - annotate it` at line 402. Newly VISIBLE rather than new: it was
  behind the vessel.py SIGSEGV, which traffic.py inherited through
  `from . import vessel`. CAUSE NOT ESTABLISHED — every isolated shape from
  line 402 compiles cleanly, so the reported line is where the pre-pass gave up
  and not necessarily where the untypeable store is. One of the last two walls
  in the lekkerzeilen corpus that is not a missing shim.
---

## The wall

    pascal26:402: error: Nil Python: cannot infer the type of field
                  self.heading - annotate it

`traffic.py:402` is:

    x, z, run, _ = route.at(along)
    self.heading = run if downstream else run + math.pi

## What it is NOT — measured, so the next reader does not re-run these

Every constituent of that line compiles on its own. Seven probes, all `ok`
against binary 84993c095465:

| shape | result |
| --- | --- |
| ternary of two float literals | ok |
| ternary of a float parameter | ok |
| bare name from a tuple unpack | ok |
| ternary over a tuple-unpacked name | ok |
| 4-way unpack from a method call | ok |
| the whole line, route as an untyped param | ok |
| 4-way unpack with a `_` throwaway | ok |

So **the boundary was not read off the failing line**, and reading it off the
failing line is what produced this list — recorded because the list is the
useful part, not the hypothesis it killed.

## Where to look instead

`self.heading` is stored in **four** places, not one:

- `402` — `run if downstream else run + math.pi`
- `546` — `self.heading = heading` (a parameter)
- `648` — `self.heading = state.heading` (a field OFF ANOTHER OBJECT)

The pre-pass decides one type per field from all of its stores, so a single
store it cannot type refuses the field, and it reports at the FIRST store
rather than the offending one. `648` is the suspect on shape — it reads a
field off `state`, whose class the pre-pass may not have — but that is a
suspect and not a finding, which is the distinction this ticket exists to
keep. **Reduce traffic.py in place** (`devdocs/progress/census/lz_census.py`
compiles one module; ast-guided statement removal did 1392 -> 9 lines on
vessel.py in 122 compiles).

## Related, and worth reading first

`refactor-n-the-field-type-pre-pass-asks-one-question-in-six-places` — six
mechanisms serving one concept is past the point CLAUDE.md calls a design flaw,
and several closed `bug-n-a-field-assigned-from-*` tickets are the same shape
fixed one arm at a time. If the sixth mechanism is why this refuses, the fix is
that refactor and not a seventh arm.
