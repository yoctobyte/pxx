---
slug: bug-n-an-aliased-from-import-binds-a-same-named-pascal-routine-the-plain-spelling-refuses
type: bug
track: N
prio: 60
status: open
summary: "FLOOR DECIDED 2026-09-21 (frankuser): a silent wrong value is ruled out by the project's own rule that real code running wrong is a bug, so both spellings must behave alike and A LOUD REFUSAL SATISFIES IT — this is NOT an open design fork and was mis-filed as one. MECHANISM CORRECTED: it is the BACKING-UNIT arm and PASCAL's case-insensitive routine lookup, not the stdlib alias table, which neither name reaches. `from random import Random as R` compiles and `R()` returns the INTEGER 0 where CPython returns an RNG object — it binds Pascal's `Random` out of the backing unit. The mechanism is a same-named Pascal routine with an accepting signature and different semantics, and the condition that springs it is an ALIAS: the plain spelling `from random import Random` refuses loudly at the call (`no overload of Random matches these arguments`) while the aliased spelling is silent. Two spellings of one import, two different answers, and the silent one is the one a program written for CPython uses. Live at HEAD and in pin v414 (binary aeadb1754b80). NOT the case-fold defect fixed in pxx@3d3d90a2d — that one is closed and this one survived it, which is how it was found."
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

## THE FORK IS NARROWER THAN THIS TICKET FIRST SAID (frankuser, 2026-09-21)

Filed saying the correct behaviour was undecided because "make the two
spellings agree" does not name a target. **That is too weak, and the project's
own rule closes the half that matters without settling anything about an RNG
class.** *Real code compiling or running wrong is a bug*, and
`from random import Random as R` is not an exotic input — it is ordinary Python
that someone MEANT to write, the spelling a style guide pushes you toward. So
one answer is ruled OUT today: **a silent wrong value.**

**The floor is that both spellings behave the same, and a LOUD REFUSAL
satisfies it.** That is decidable now, costs nothing, pre-empts nobody, and it
makes the shadowing hazard below impossible to hit silently — which was the
actual danger. Reproduced independently under the pin before this was written.

## MECHANISM CORRECTED: it is the UNIT arm and Pascal case-insensitivity

This ticket first implied the stdlib alias table. It is not that. Measured
2026-09-21 at HEAD:

    from math import Sqrt as S ; print(S(9))   ->  3.0     (Pascal `Sqrt`)
    from math import sqrt as s ; print(s(9))   ->  3.0
    from random import Random as R ; print(R())  ->  0
    from random import Random as R ; print(R(0)) ->  0     (identical)

`PyStdProvidesMember` answers FALSE for both `math.Sqrt` and `random.Random`
once the member is matched as spelled, so **neither reaches `PyStdAliasRecord`
at all.** Both are bound by the BACKING-UNIT arm, where Pascal's
case-insensitive routine lookup matches `Sqrt` to `sqrt` and `Random` to
`Random`. So the case-insensitivity here is **Pascal's, leaking into Python name
resolution** — not the fold that pxx@3d3d90a2d removed.

`R()` and `R(0)` give the same answer, so the no-argument call is reaching
Pascal's `Random(n)` with a zero, not Pascal's argumentless `Random: Real`.

**AND THIS CONFIRMS THE KEY-SPACE CENSUS BY A ROUTE THAT WAS NOT TESTED WHEN IT
WAS WRITTEN.** The census says `math` has no case-collision, so a fold there can
only accept what CPython rejects — and `Sqrt as S` is exactly that: accepted by
us, rejected by CPython, harmless. The argument predicted the behaviour of a
name nobody had tried, which is the property an observational census does not
have.

## What a fix MUST NOT break

`from math import sqrt as s` and `from random import randint as ri` both work
and are genuine Python. Any rule that refuses `Random as R` by requiring the
member to be a Python-facing name has to keep those. **`Sqrt as S` may be
refused** — CPython rejects it too — but that is a widening of the blast radius
beyond the floor above, so it should be a stated decision rather than a side
effect.

**Not attempted here.** The binding site is shared by every
`from <unit> import <name>`, so the change is a name-resolution rule and not a
local repair; landing it needs a full tier rather than the quick one. Banked
rather than microfixed.

## What would retire THIS ticket

`from random import Random as R` either refusing (agreeing with the plain
spelling) or binding the real RNG class once that feature lands. Both spellings
must be in the fixture — the whole defect is that they disagree, so a row
covering only one certifies the other.

Positive control: the fixture must fail on a build where the alias arm binds the
Pascal routine. Pin v414 is that build, so it needs no manufacturing — run the
row against `stable_linux_amd64/default/pinned` and it must return 0.
