---
slug: feature-n-random-random-has-no-per-instance-rng-class-and-the-state-machinery-already-exists
type: feature
track: N
prio: 45
status: open
summary: "`random.Random(seed)` has no per-instance RNG — TSP's smoke.py and commentary.py each want one so a run is reproducible from a seed without disturbing the global stream. The per-instance STATE already exists and is complete: `lib/rtl/random.pas` has `TRandomState` with Seed/Randomize/Next/Range/Range64/Double/Bytes/Split. What is missing is a way to REACH it: plain `import random` is consumed-only, so `random` is not bound to its unit and `random.Random` cannot resolve to a class there. The silent half of this is already fixed separately — `random.Random` used to fold onto `random.random` and evaluate to a float; it is now loud. This ticket is only the feature."
---

# `random.Random` has no per-instance RNG, and the state machinery already exists

Row 7 of `devdocs/dev/tsp-compile-wall-inventory-2026-09-20.md`, second half.
The FIRST half — a silent wrong value — is fixed and is not this ticket; see
`devdocs/dev/tsp-rows-4-8-what-shares-a-cause.md`. In short: the intercept
table's callers lower-cased the member, `random.Random` folded onto
`random.random`, and `random.Random()` compiled to a **float**. The member is now
matched as spelled, so the call is refused rather than silently wrong.

## What the callers want

    tsp/smoke.py:60        self.rng = random.Random(seed)
    tsp/commentary.py:64   rng = random.Random(mission_id)

Both want the same thing and it is the reason `Random` exists in CPython: a
stream that is **reproducible from a seed** and **independent of the global
one**, so a seeded replay is not perturbed by anything else in the program that
draws a number.

`random.seed(n)` plus the module-level functions is NOT a substitute, and
offering it as one would be the wrong fix: it makes the replay depend on every
other consumer of the global stream.

## The state is already here, in full

`lib/rtl/random.pas` already declares a per-instance state record and its whole
API:

    TRandomState
    RandomStateSeed / RandomStateRandomize / RandomStateNext
    RandomStateRange / RandomStateRange64 / RandomStateDouble
    RandomStateBytes / RandomStateSplit

So this is not "implement an RNG". It is a class wrapping a record that exists,
with the Python method names (`random`, `randint`, `randrange`, `uniform`,
`choice`, `shuffle`, `seed`) on it.

## THE ACTUAL BLOCKER IS REACHABILITY, NOT THE CLASS

Plain `import random` is **consumed-only** (`PyImportRootPlainIsConsumedOnly`),
so `random` is not bound to `lib/rtl/random` as a unit alias, and a qualified
`random.Random` has no unit to find a class in. That is consistent with the
diagnostic the fixed compiler now gives — `undefined variable (random)`, i.e.
the name is not bound at all rather than bound to something without that member.

Note the asymmetry already recorded in `pyparser.inc`: the FROM-spelling
(`from random import randint`) takes the unit arm, while the PLAIN spelling is
consumed. So the two import spellings of the same module reach different
machinery, and a fix has to decide which one `random.Random` goes through.
**Whoever takes this should read that comment before choosing** — the two
spellings have been out of step in both directions before
(`bug-n-from-sys-import-fails-while-import-sys-works`).

## Two name hazards, both real, both cheap to hit

- **`Random` is a Pascal RTL function name.** A class of that name inside unit
  `random` collides with `System.Random`.
- **A class named after a unit in its own `uses` clause silently miscompiles its
  own constructor into a self-call** — `lib/rtl/pil.pas` records the measurement
  and works around it with `Image = TPILImage`. A class called `Random` in a
  unit called `random` is that shape.

The established workaround is the alias, which carries its own known cost:
`type(x).__name__` then reports the Pascal spelling
(`bug-n-a-shim-class-reports-its-pascal-spelling-from-type-name`). Acceptable
here — neither caller introspects the RNG — but it should be a decision and not
a discovery.

## What would retire this

`smoke.py` past line 60, and a fixture asserting the property the class exists
for: **two `Random(1234)` instances produce the SAME sequence, and drawing from
the global `random` in between does not change it.** A test that only checks
"returns a number in range" passes against the global stream and certifies the
bug. Seed with a value whose first draw differs from the global stream's, or the
row cannot fail.


## ABSORBED FROM ITS DUPLICATE, 2026-09-21

`feature-n-random-random-the-per-instance-rng-class-is-absent` (p40) was the
same feature filed a day earlier by the same seat, and is resolved as
superseded by this one. Both were mine; neither carried a `supersedes` edge,
and both sat in BOARD.md as live work. Reported by frankz-e5 off the TSP
survey.

**Why THIS one is the survivor rather than the older:** the p40 summary framed
the gap around a CONDITION that no longer holds — that the NilPy member lookup
folds case, so `Random` matched the module-level `random()` and the program was
refused with `pyrandom_random takes fewer arguments than were given`. **That
fold was fixed on 2026-09-21** (the member is now matched as spelled), so a
reader taking p40 at face value would have gone looking for an arity message
that the compiler no longer emits. Its diagnosis was correct when written and
its repro still reproduces — with a different, better error.

**The one thing in p40 worth keeping, because it is a CLASS and not this
ticket:** any absent member whose name differs only in case from a present one
used to be reported as an ARITY error about a call the source never wrote,
which sends the reader to the call site instead of to the missing member. That
is retired as a live hazard by the as-spelled fix, and it is recorded where a
retired hazard belongs — the logbook and the case-sensitivity work — rather
than in a feature ticket, so it cannot be mistaken for something still to do.

**p40's repro, kept because it is three lines and still the shortest statement
of what is wanted:**

```python
import random
r = random.Random(7)
print(type(r).__name__)      # CPython: Random
```
