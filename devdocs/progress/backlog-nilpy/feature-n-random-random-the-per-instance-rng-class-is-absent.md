---
slug: feature-n-random-random-the-per-instance-rng-class-is-absent
title: random.Random — the per-instance RNG class — is absent, and its absence is reported as a wrong-arity call
track: N
type: feature
prio: 40
status: backlog
owner: ""
created: 2026-09-20
found-by: frankH
tags: [nilpy, random, rtl, diagnostic]
blocked-by: []
summary: "MECHANISM: lib/rtl/random.pas exposes a single global generator (XoshiroSeed/Random64/RandomDouble/RandRange) and a re-entrant TRandomState beside it, but NO Python-surface `Random` CLASS, so `r = random.Random(seed)` has nothing to bind to. The CONDITION that makes it expensive is separate from the absence: the NilPy member lookup folds case, so `Random` matches the module-level `random()` function and the program is refused with `pyrandom_random takes fewer arguments than were given` -- an ARITY message about a call the source never wrote, which sends the reader to the call site instead of to the missing member. Any absent member whose name differs only in case from a present one has this shape; `Random`/`random` is the instance that a real program hit. The raw materials are already there: TRandomState with RandomStateSeed/Next/Range/Double/Bytes/Split is exactly the per-instance state `random.Random` needs, so the work is a Python-surface class over it (seed, random, randint, randrange, choice, shuffle, uniform, gauss), not new generator code. FIXING THE DIAGNOSTIC IS NOT FIXING THIS TICKET and is tracked with the case-folding family -- exactness turns the message honest and leaves the program refused."
---

# random.Random is absent; the folding makes it look like an arity error

Found 2026-09-20 (frankH) censusing That Space Program under NilPy.
`tsp/smoke.py:60` is `self.rng = random.Random(seed)` and is the only wall in
that file.

Repro, three lines, and CPython prints `Random`:

```python
import random
r = random.Random(7)
print(type(r).__name__)
```

pxx: `pascal26:2: error: Nil Python: pyrandom_random takes fewer arguments than
were given`.

A per-instance generator is what a program uses when it wants a REPRODUCIBLE
stream that other code cannot disturb — a seeded simulation, a test fixture, a
procedural world — which is precisely why `smoke.py` asks for one. Mapping it
onto the global generator would be the wrong answer rather than a partial one:
every other user of `random.*` in the process would perturb the stream, so a
seeded run would stop being reproducible and nothing would say so.
