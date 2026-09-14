---
slug: bug-n-the-property-conflict-warning-misses-five-of-eight-conflicts-including-the-one-that-crashed
title: the property-conflict warning misses five of eight conflicts, including the one that crashed
summary: >
  `several unrelated classes declare a .X property` fires on 4 of the 15 names
  that have two or more `@property` declarers in lekkerzeilen. Restricted to the
  cleanest population — the EIGHT names declared as a property by both `Region`
  and `World`, same file, same construct, same class pair — it fires on three
  and is silent on five. One of the five silent ones is `.flow`, which is the
  exact name that produced the SIGSEGV we spent 2026-09-14 chasing and the
  `'World' object has no attribute 'flow'` that the import-order perturbation
  produced. The warning is real and useful; the gap is that its absence reads as
  a clean bill of health and is not one.
track: N
type: bug
prio: 45
owner: unassigned
status: open  # mechanism found; fix building at the compiler seat
---

## Why this is worth a ticket rather than a shrug

The warning is good. It is also, on this program, the thing a user would check
BEFORE trusting a dynamic property read — and on the one name that actually
killed the process it says nothing at all. That is the failure mode we named
three separate times today: an instrument whose silence is read as a negative
result. This is the compile-time instance of it.

## The population, measured

Compiler `934ba0418`, lekkerzeilen at the owner's HEAD, built with
`--threadsafe -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES`. 122-line build
log. Names with two or more `@property` declarers anywhere in the package:

| name | declarers | warnings emitted |
| --- | --- | --- |
| `attribution` | world.py:284, world.py:1060 | 3 |
| `spawn` | world.py:278, world.py:1064 | 13 |
| `up` | rig.py:137, sim.py:82 | 3 |
| `water_level` | world.py:274, world.py:1069 | 9 |
| `bed` | world.py:316, world.py:1265 | **0** |
| `canopy` | world.py:339, world.py:1269 | **0** |
| `cover` | world.py:327, world.py:877 | **0** |
| `flow` | world.py:344, world.py:1273 | **0** |
| `height` | ui.py x5 | **0** |
| `length` | traffic.py:133, traffic.py:409 | **0** |
| `name` | world.py:270, world.py:1051, traffic.py:425 | **0** |
| `origin` | world.py:256, world.py:1055 | **0** |
| `size` | platform/_ctypes_backend.py:47, platform/_pxx.py:714 | **0** |
| `tabbed` | ui.py:548, ui.py:755 | **0** |
| `value` | ui.py:239, ui.py:314 | **0** |

4 of 15. Several of the silent rows may be silent CORRECTLY — if a name is never
read through a receiver whose class is not statically known, there is nothing to
warn about. So that table on its own does not establish a bug.

## The controlled contrast, which does

`Region` (world.py:175-375) and `World` (world.py:963-) both declare EIGHT of
these as `@property`. Same file, same construct, same pair of classes, so
everything the table above leaves varying is held fixed:

| name | Region | World | warns |
| --- | --- | --- | --- |
| `water_level` | 274 | 1069 | YES (9) |
| `spawn` | 278 | 1064 | YES (13) |
| `attribution` | 284 | 1060 | YES (3) |
| `origin` | 256 | 1055 | no |
| `name` | 270 | 1051 | no |
| `bed` | 316 | 1265 | no |
| `canopy` | 339 | 1269 | no |
| `flow` | 344 | 1273 | no |

Three warn, five do not, out of one structurally uniform population.

## `.flow` is not an arbitrary member of the silent five

It is the name from the crash. `app.py:1243` is
`self.env.flow = source.flow if source else None`, and `app.py:681` passes
`flow=source.flow if source else None`. `source` is the receiver whose class is
not statically known — it is the read that faulted, and when the import order
was perturbed it became `AttributeError: 'World' object has no attribute
'flow'`, which is the compiler resolving `.flow` somewhere `World` could not
satisfy. So this name is dynamically dispatched, has two conflicting property
declarers, and is the one the warning does not mention.

`water_level` is dispatched the same way — `region.water_level` at app.py:662,
677 and `self.region.water_level` at 1283, receiver class not statically known —
and produces nine warnings.

## MECHANISM FOUND — and my own hypothesis 1 was right, killed by a bad instrument

Found by the compiler seat in `PyMakeVariantPropRecv` (`compiler/pyparser.inc`),
by construction rather than by census. The first loop:

```pascal
for c := 0 to UClsCount - 1 do
  if (not UClsIsRecord[c]) and (FindUField(c, pname) >= 0) then Exit;
```

It exits as soon as ANY non-record class declares a real FIELD of that name,
which is correct — the caller's field branch owns that access — but it exited
with `ambig` still False, so ambiguity was never computed and the caller neither
resolved nor warned. **One unrelated field named X anywhere in the program
silences the diagnosis for X across the entire program.** Constructed pair:

| program | warnings |
| --- | --- |
| two unrelated `@property` declarers | 3 |
| same, plus one unrelated class with `self.flow = 99` | **0** |
| same, after the fix | 3 |

The read/store fork is NOT the silencer: `ambig := True` is set before it and a
read exits with `ambig` True, so reads do warn.

### The correction I owe this ticket

An earlier revision listed "a plain attribute declarer suppresses it" as a
hypothesis I had TESTED AND KILLED. It was substantively RIGHT, and I killed it
with an instrument that does not measure what it claimed. My counter-example was
`.up`: three textual `self.up = ` assignments (app.py:308, 427, 443) and it warns
anyway. But `FindUField` counts declared fields of a class, and a textual
`self.X =` in a method body is not the same population. The correlation I
discarded was real; the refutation was an artifact.

The compiler seat independently hit the identical trap from the other side — a
perfect 8/8 correlation between `grep -c 'self\.X *='` and my eight rows, then
`.up` falsified it there too. Two seats, same wrong instrument, opposite
conclusions drawn from it, and only a CONSTRUCTED two-class pair settled it.

That is the reusable lesson and it is worth more than the bug: a census over
real source can only correlate, and a correlation refuted by a miscounted row
looks exactly like a correlation refuted by a real one. Build the pair.


## What I would want from a fix

Not necessarily more warnings. If the silence on `origin`, `name`, `bed` and
`canopy` is correct because nothing dispatches on them dynamically, then the
only wrong row is `flow`, and the question is narrow: why does a dispatched,
two-property-declarer name emit nothing when its sibling in the same class pair
emits nine. If instead the warning is missing a whole category of dispatch
sites, the blast radius is every silent row, and that is worth knowing before
anyone reads a quiet build as a safe one.

## Gate

A `.npy` fixture with two classes each declaring the same name as `@property`,
read through a receiver of unknown class, asserting the warning fires — plus the
negative control of a name declared by only one class, asserting it does not.
The lekkerzeilen build is the integration check: `.flow` should warn, or the
ticket should record why it correctly should not.

## Log
- 2026-09-14 — filed from the lekkerzeilen seat at compiler 934ba0418. Table and
  contrast measured from the build log of the owner's pristine tree; file is
  UNTRACKED and nothing already tracked was touched.
