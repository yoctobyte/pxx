---
slug: bug-n-an-aliased-from-import-binds-a-same-named-pascal-routine-the-plain-spelling-refuses
type: bug
track: N
prio: 60
status: open
summary: "`from random import Random as R` compiles and `R()` returns the INTEGER 0 where CPython returns an RNG object — it binds Pascal's `Random` out of the backing unit. The mechanism is a same-named Pascal routine with an accepting signature and different semantics, and the condition that springs it is an ALIAS: the plain spelling `from random import Random` refuses loudly at the call (`no overload of Random matches these arguments`) while the aliased spelling is silent. Two spellings of one import, two different answers, and the silent one is the one a program written for CPython uses. Live at HEAD and in pin v414 (binary aeadb1754b80). NOT the case-fold defect fixed in pxx@3d3d90a2d — that one is closed and this one survived it, which is how it was found."
---

# An aliased from-import binds a same-named Pascal routine the plain spelling refuses

Found 2026-09-21 while closing the case-fold class, by asking what ELSE reaches
the stdlib tables. It is a different mechanism that happens to share a name with
the bug that exposed it, which is why it needed its own ticket rather than a
line in that one.

## Reproduced at HEAD and on the pin

    from random import Random as R
    print(R())              # CPython: <random.Random object ...>   pxx: 0
    print(R(10) < 10)       # pxx: True

`R(10) < 10` is what identifies it: that is Pascal's `Random(n)`, which returns
`0..n-1`. The name is bound to the routine in the backing unit `lib/rtl/random.pas`
(and/or `System.Random`), not to anything Python means by `random.Random`.

## THE CONDITION THAT SPRINGS IT IS THE ALIAS, AND THAT IS THE WHOLE FINDING

    from random import Random           -> REFUSED: no overload of Random matches these arguments
    from random import Random as R      -> COMPILES, returns 0

**One import, two spellings, two different answers, and the LOUD one is the
spelling a CPython programmer is less likely to write.** `Random as R` is
ordinary Python style. So the arrangement that is silent is not the exotic one.

This is the tree's own rule arriving again: *the sibling is usually a SPELLING,
not a shape, which is why grepping for the construct misses it.* Grepping for
`Random` finds both arms; only running both separates them.

## What it is NOT

- **Not the case-fold bug.** pxx@3d3d90a2d made the stdlib call table match the
  member as spelled. That is closed — see the census below — and this survived
  it. Do not read this ticket as a regression of that fix.
- **Not an unprovided-member bug.** `from random import NoSuchThing as Q` is
  correctly refused with `undefined variable (Q)`. The alias machinery rejects
  members nothing provides; the defect is that it ACCEPTS one that a Pascal
  routine happens to provide under the same spelling.

## Why 60

A program asking for a seeded RNG gets an integer and can go on computing with
it. There is no diagnostic, no crash, and the value is plausible — the tree's
expensive shape. Against that: `random.Random` is the one name in the whole
admitted key space where this can happen (see below), so the blast radius is
one name today, and it is bounded by a Pascal routine existing under the same
spelling in a backing unit.

It is above the floor because the mechanism is general and the population grows
with every `mimic_` unit that gains a Pascal-named routine, and because
`feature-n-random-random-has-no-per-instance-rng-class-...` will be implemented
on exactly this name — whoever does that must know the alias arm exists, or the
class will be shadowed by the routine for the aliased spelling only.

## THE KEY-SPACE CENSUS THAT BOUNDS IT, and that closes the case-fold class

Method is the one from pxx@3d3d90a2d: reason over the key space rather than
sample spellings, so the answer covers names nobody has written yet.

Question: within a module the dispatcher admits, do two REAL CPython attributes
differ only by case? If none do, a case-fold can only ever accept a name CPython
REJECTS — which is upward-compatible and a feature under the N rule, not a
defect.

Population: every attribute of the eight importable admitted bases, against
CPython 3.14.4.

    os 427 · sys 115 · textwrap 17 · select 38 · math 67 · time 44 · collections 38
    random: COLLISION -> ['Random', 'random']

    816 attributes examined, exactly 1 case-collision.

**So `random.Random` is the only name in the admitted key space where a
case-fold can return the wrong KIND of thing.** Everywhere else — `sys.ARGV`,
`os.SEP`, both verified to compile — the fold accepts what CPython rejects, and
that is the one direction NilPy is allowed to differ in.

That is the case-fold class closed by argument rather than by spot-checks, and
it is a NULL result: nothing else folds harmfully, and the one name that could
is the one already fixed.

## What would retire THIS ticket

`from random import Random as R` either refusing (agreeing with the plain
spelling) or binding the real RNG class once that feature lands. Both spellings
must be in the fixture — the whole defect is that they disagree, so a row
covering only one certifies the other.

Positive control: the fixture must fail on a build where the alias arm binds the
Pascal routine. Pin v414 is that build, so it needs no manufacturing — run the
row against `stable_linux_amd64/default/pinned` and it must return 0.
