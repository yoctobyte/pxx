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
